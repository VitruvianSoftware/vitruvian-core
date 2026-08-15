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

/**
 * ConfirmModal component
 *
 * A reusable confirmation dialog for destructive actions.
 */

import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Plate, Button } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface ConfirmModalProps {
  open: boolean;
  title: string;
  message: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export const ConfirmModal: React.FC<ConfirmModalProps> = ({
  open,
  title,
  message,
  onConfirm,
  onCancel,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className={
            useDesignSystem
              ? "modal-overlay"
              : "modal-overlay glassmorphic-overlay"
          }
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            backgroundColor: useDesignSystem
              ? "rgba(31, 29, 26, 0.4)"
              : undefined,
            backdropFilter: "blur(4px)",
            zIndex: 9999,
          }}
          onClick={onCancel}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2 }}
        >
          {useDesignSystem ? (
            <motion.div
              style={{
                minWidth: "320px",
                maxWidth: "420px",
                width: "90%",
                padding: "24px",
                backgroundColor: "var(--paper, #fbf7ee)",
                border: "1px solid var(--ink, #1f1d1a)",
                boxShadow: "4px 4px 0px 0px var(--ink, #1f1d1a)",
              }}
              onClick={(e: React.MouseEvent) => e.stopPropagation()}
              initial={{ opacity: 0, scale: 0.96, y: 12 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: 12 }}
              transition={{ duration: 0.15, ease: "easeOut" }}
            >
              <Plate marks enter>
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                  }}
                >
                  <span
                    style={{
                      fontFamily: "var(--font-mono, monospace)",
                      fontSize: "10px",
                      fontWeight: 700,
                      textTransform: "uppercase",
                      letterSpacing: "0.08em",
                      color: "var(--accent, #991b1b)",
                      border: "1px solid var(--accent, #991b1b)",
                      padding: "1px 4px",
                    }}
                  >
                    WARN
                  </span>
                  <h3
                    style={{
                      margin: 0,
                      fontSize: "16px",
                      fontWeight: 600,
                      color: "var(--ink, #1f1d1a)",
                    }}
                  >
                    {title}
                  </h3>
                </div>

                <p
                  style={{
                    margin: "12px 0 16px 0",
                    color: "var(--paper-dim, #736d64)",
                    fontSize: "13px",
                    lineHeight: 1.5,
                  }}
                >
                  {message}
                </p>

                <div
                  style={{
                    display: "flex",
                    justifyContent: "flex-end",
                    gap: "8px",
                    marginTop: "8px",
                  }}
                >
                  <Button variant="ghost" size="sm" onClick={onCancel}>
                    Cancel
                  </Button>
                  <Button
                    variant="solid"
                    size="sm"
                    style={{
                      backgroundColor: "var(--accent, #991b1b)",
                      borderColor: "var(--accent, #991b1b)",
                      color: "#ffffff",
                    }}
                    onClick={onConfirm}
                  >
                    Delete
                  </Button>
                </div>
              </Plate>
            </motion.div>
          ) : (
            <motion.div
              className="glassmorphic-modal"
              style={{
                borderRadius: "8px",
                padding: "24px",
                minWidth: "320px",
                maxWidth: "400px",
              }}
              onClick={(e: React.MouseEvent) => e.stopPropagation()}
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              transition={{ duration: 0.2, ease: "easeOut" }}
            >
              <h3
                style={{
                  margin: "0 0 12px 0",
                  fontSize: "18px",
                  fontWeight: 600,
                  color: "var(--color-text-primary)",
                }}
              >
                {title}
              </h3>
              <p
                style={{
                  margin: "0 0 24px 0",
                  color: "var(--color-text-secondary)",
                  fontSize: "14px",
                  lineHeight: 1.5,
                }}
              >
                {message}
              </p>
              <div
                style={{
                  display: "flex",
                  justifyContent: "flex-end",
                  gap: "12px",
                }}
              >
                <button className="btn btn-secondary" onClick={onCancel}>
                  Cancel
                </button>
                <button
                  className="btn btn-primary"
                  style={{ backgroundColor: "var(--color-accent-danger)" }}
                  onClick={onConfirm}
                >
                  Delete
                </button>
              </div>
            </motion.div>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
};
