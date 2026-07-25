import * as React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Dialog, Banner } from "./Overlay";
import { Button } from "./Button";
import { Field, Input } from "./Form";
import { Plate } from "./Plate";

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
