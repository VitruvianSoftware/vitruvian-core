/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import React, { useEffect, useState } from "react";
import { Modal } from "../Modal";
import { EmptyState } from "../EmptyState";
import { EmptySpacesIllustration } from "../illustrations/EmptySpaces";
import { EmptyResourcesIllustration } from "../illustrations/EmptyResources";
import { EmptyTabsIllustration } from "../illustrations/EmptyTabs";
import { Button, Input } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../../constants/features";

export interface OnboardingModalProps {
  isOpen: boolean;
  /** User dismissed the flow (Skip / close). The caller persists completion. */
  onSkip: () => void;
  /** User finished all steps. The caller persists completion. */
  onComplete: () => void;
  onCreateSpace: (name: string) => void | Promise<void>;
  onAddResource: (input: {
    title: string;
    url: string;
  }) => void | Promise<void>;
  onSaveTabs: () => void | Promise<void>;
}

const TOTAL_STEPS = 3;

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "8px 12px",
  fontSize: "13px",
  borderRadius: "6px",
  border: "1px solid var(--color-border)",
  background: "var(--color-bg-card, #fff)",
  color: "var(--color-text-primary)",
  outline: "none",
};

/**
 * First-run onboarding: a 3-step guided flow (create a space → add a resource →
 * save your tabs) that performs the real actions on real data, mirroring
 * Workona's "set up by doing it in the app" approach. See #138.
 */
export const OnboardingModal: React.FC<OnboardingModalProps> = ({
  isOpen,
  onSkip,
  onComplete,
  onCreateSpace,
  onAddResource,
  onSaveTabs,
}) => {
  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [spaceName, setSpaceName] = useState("");
  const [resTitle, setResTitle] = useState("");
  const [resUrl, setResUrl] = useState("");
  const [tabsSaved, setTabsSaved] = useState(false);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  // Reset to the first step whenever the flow is (re)opened — e.g. replayed
  // from Settings after it was already completed.
  useEffect(() => {
    if (isOpen) {
      setStep(0);
      setTabsSaved(false);
    }
  }, [isOpen]);

  const advance = () => setStep((s) => Math.min(s + 1, TOTAL_STEPS - 1));
  const back = () => setStep((s) => Math.max(s - 1, 0));

  const run = async (
    action: () => void | Promise<void>,
    after?: () => void,
  ) => {
    if (busy) return;
    setBusy(true);
    try {
      await action();
      after?.();
    } finally {
      setBusy(false);
    }
  };

  const steps = [
    {
      title: "Create a space",
      description:
        "Spaces keep each project's tabs, resources, notes, and tasks together. Start with your first one.",
      illustration: <EmptySpacesIllustration />,
      body: useDesignSystem ? (
        <Input
          placeholder="Space name"
          aria-label="Space name"
          value={spaceName}
          onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
            setSpaceName(e.target.value)
          }
          style={{ width: "100%" }}
        />
      ) : (
        <input
          type="text"
          placeholder="Space name"
          aria-label="Space name"
          value={spaceName}
          onChange={(e) => setSpaceName(e.target.value)}
          style={inputStyle}
        />
      ),
      primaryLabel: "Create space",
      primaryDisabled: !spaceName.trim(),
      onPrimary: () => run(() => onCreateSpace(spaceName.trim()), advance),
    },
    {
      title: "Add a resource",
      description:
        "Save the links, docs, and tools you keep coming back to — right inside the space.",
      illustration: <EmptyResourcesIllustration />,
      body: (
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: "8px",
            width: "100%",
          }}
        >
          {useDesignSystem ? (
            <>
              <Input
                placeholder="Title"
                aria-label="Resource title"
                value={resTitle}
                onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                  setResTitle(e.target.value)
                }
              />
              <Input
                type="url"
                placeholder="https://..."
                aria-label="Resource URL"
                value={resUrl}
                onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                  setResUrl(e.target.value)
                }
              />
            </>
          ) : (
            <>
              <input
                type="text"
                placeholder="Title"
                aria-label="Resource title"
                value={resTitle}
                onChange={(e) => setResTitle(e.target.value)}
                style={inputStyle}
              />
              <input
                type="url"
                placeholder="https://..."
                aria-label="Resource URL"
                value={resUrl}
                onChange={(e) => setResUrl(e.target.value)}
                style={inputStyle}
              />
            </>
          )}
        </div>
      ),
      primaryLabel: "Add resource",
      primaryDisabled: !resUrl.trim(),
      onPrimary: () =>
        run(
          () => onAddResource({ title: resTitle.trim(), url: resUrl.trim() }),
          advance,
        ),
    },
    {
      title: "Save your tabs",
      description:
        "Snapshot the tabs you have open into this space — reopen them anytime, on any device.",
      illustration: <EmptyTabsIllustration />,
      body: useDesignSystem ? (
        <Button
          variant="secondary"
          onClick={() =>
            run(
              () => onSaveTabs(),
              () => setTabsSaved(true),
            )
          }
          disabled={busy || tabsSaved}
        >
          {tabsSaved ? "Tabs saved" : "Save my current tabs"}
        </Button>
      ) : (
        <button
          type="button"
          className="btn btn-secondary"
          onClick={() =>
            run(
              () => onSaveTabs(),
              () => setTabsSaved(true),
            )
          }
          disabled={busy || tabsSaved}
        >
          {tabsSaved ? "Tabs saved" : "Save my current tabs"}
        </button>
      ),
      primaryLabel: "Finish",
      primaryDisabled: false,
      onPrimary: onComplete,
    },
  ];

  const current = steps[step];

  const footer = (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        width: "100%",
        gap: "12px",
      }}
    >
      <div style={{ display: "flex", gap: "6px" }} aria-hidden="true">
        {steps.map((_, i) => (
          <span
            key={i}
            style={{
              width: useDesignSystem ? "8px" : "7px",
              height: useDesignSystem ? "8px" : "7px",
              borderRadius: useDesignSystem ? "0" : "50%",
              background:
                i === step
                  ? "var(--color-accent-primary)"
                  : "var(--color-border)",
            }}
          />
        ))}
      </div>
      <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
        {useDesignSystem ? (
          <>
            <Button variant="ghost" size="sm" onClick={onSkip}>
              Skip
            </Button>
            {step > 0 && (
              <Button
                variant="secondary"
                size="sm"
                onClick={back}
                disabled={busy}
              >
                Back
              </Button>
            )}
            <Button
              variant="primary"
              size="sm"
              onClick={current.onPrimary}
              disabled={current.primaryDisabled || busy}
            >
              {current.primaryLabel}
            </Button>
          </>
        ) : (
          <>
            <>
              {useDesignSystem ? (
                <Button
                  variant="secondary"
                  size="sm"
                  type="button"
                  onClick={onSkip}
                >
                  {" "}
                  Skip{" "}
                </Button>
              ) : (
                <button
                  type="button"
                  className="btn btn-secondary btn-sm"
                  onClick={onSkip}
                >
                  Skip
                </button>
              )}
            </>
            {step > 0 && (
              <>
                {useDesignSystem ? (
                  <Button
                    variant="secondary"
                    size="sm"
                    type="button"
                    onClick={back}
                    disabled={busy}
                  >
                    {" "}
                    Back{" "}
                  </Button>
                ) : (
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={back}
                    disabled={busy}
                  >
                    Back
                  </button>
                )}
              </>
            )}
            <>
              {useDesignSystem ? (
                <Button
                  variant="primary"
                  size="sm"
                  type="button"
                  onClick={current.onPrimary}
                  disabled={current.primaryDisabled || busy}
                >
                  {" "}
                  {current.primaryLabel}{" "}
                </Button>
              ) : (
                <button
                  type="button"
                  className="btn btn-primary btn-sm"
                  onClick={current.onPrimary}
                  disabled={current.primaryDisabled || busy}
                >
                  {current.primaryLabel}
                </button>
              )}
            </>
          </>
        )}
      </div>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onSkip}
      title="Get started with Tabula"
      size="medium"
      footer={footer}
    >
      <EmptyState
        illustration={current.illustration}
        title={current.title}
        description={current.description}
        action={current.body}
      />
    </Modal>
  );
};
