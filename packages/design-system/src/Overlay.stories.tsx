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
import * as React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Dialog, Banner } from "./Overlay.js";
import { Button } from "./Button.js";
import { Field, Input } from "./Form.js";
import { Plate } from "./Plate.js";

const overlayMeta: Meta = {
  title: "Components/Overlay",
  parameters: { layout: "padded" },
};
export default overlayMeta;

export const DestructiveDialog: StoryObj = {
  render: function Render() {
    const [open, setOpen] = React.useState(true);
    return (
      <Plate field="lg" className="p-6 min-h-[320px]">
        <Button onClick={() => setOpen(true)}>Open dialog</Button>
        <Dialog
          open={open}
          onDismiss={() => setOpen(false)}
          destructive
          kicker="Destructive · irreversible"
          title="Destroy edge-03?"
          actions={
            <>
              <Button variant="ghost" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button variant="danger">Destroy cluster</Button>
            </>
          }
        >
          <p className="dialog-body">
            Two nodes and 14 workloads will be torn down. Persistent volumes are
            retained for 7 days, then deleted. This cannot be undone from the
            console.
          </p>
          <Field label="Type the cluster name to confirm">
            <Input placeholder="edge-03" />
          </Field>
        </Dialog>
      </Plate>
    );
  },
};

export const Banners: StoryObj = {
  render: () => (
    <div className="flex flex-col gap-3">
      <Banner tone="info">
        <strong>Candidate revision live at 0% traffic.</strong> Smoke suite
        passes in 4m 12s.
      </Banner>
      <Banner tone="warn">
        <strong>Version drift on edge-03.</strong> kubelet 1.31.9 behind the
        pinned 1.32.4.
      </Banner>
      <Banner tone="err">
        <strong>Artifact registry auth failed — exit 13.</strong> Rotate the
        deployer token with <code>devx auth refresh</code>.
      </Banner>
    </div>
  ),
};
