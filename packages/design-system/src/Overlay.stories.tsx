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
import {
  Dialog,
  Banner,
  Menu,
  MenuItem,
  MenuDivider,
  Toast,
  Tooltip,
  Popover,
  CommandPalette,
  Drawer,
} from "./Overlay.js";
import { Button } from "./Button.js";
import { Field, Input } from "./Form.js";
import { Plate } from "./Plate.js";
import { Kbd } from "./Tag.js";

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

export const MenusAndToasts: StoryObj = {
  render: function Render() {
    const [popOpen, setPopOpen] = React.useState(false);
    return (
      <div className="grid grid-cols-2 gap-6 items-start">
        <Menu style={{ maxWidth: 260 }}>
          <MenuItem>
            Inspect manifest <Kbd>⌘I</Kbd>
          </MenuItem>
          <MenuItem>
            Copy workload ARN <Kbd>⌘C</Kbd>
          </MenuItem>
          <MenuDivider />
          <MenuItem destructive>
            Cordon &amp; drain node <Kbd>⌫</Kbd>
          </MenuItem>
        </Menu>
        <div className="flex flex-col gap-4">
          <Toast
            tone="ok"
            title="Promotion complete"
            message="tabula-web@0.14.2 is serving 100% of production traffic."
          />
          <Toast
            tone="warn"
            title="Seal key rotation due"
            message="k3s sealed-secrets master key reaches 30d threshold tomorrow."
          />
          <div className="flex items-center gap-4">
            <Tooltip content="Force immediate GitOps reconciliation">
              <Button size="sm">Hover for tooltip</Button>
            </Tooltip>
            <Popover
              open={popOpen}
              trigger={
                <Button size="sm" onClick={() => setPopOpen((v) => !v)}>
                  Toggle popover
                </Button>
              }
            >
              <div className="label mb-2">ACTIVE LEASE</div>
              <div className="mono text-xs">holder: ridge-bot · ttl: 42s</div>
            </Popover>
          </div>
        </div>
      </div>
    );
  },
};

export const CommandPaletteAndDrawer: StoryObj = {
  render: function Render() {
    const [cmdOpen, setCmdOpen] = React.useState(false);
    const [drawerOpen, setDrawerOpen] = React.useState(false);
    const [query, setQuery] = React.useState("");
    return (
      <div className="flex gap-4">
        <Button variant="primary" onClick={() => setCmdOpen(true)}>
          Open Command Palette
        </Button>
        <Button onClick={() => setDrawerOpen(true)}>
          Open Inspection Drawer
        </Button>
        <CommandPalette
          open={cmdOpen}
          query={query}
          onQueryChange={setQuery}
          onDismiss={() => setCmdOpen(false)}
          items={[
            {
              id: "sync",
              group: "CLUSTER",
              label: "Sync ArgoCD applications",
              shortcut: "⌘S",
            },
            {
              id: "logs",
              group: "CLUSTER",
              label: "Tail workload logs",
              shortcut: "⌘L",
            },
            {
              id: "theme",
              group: "VIEW",
              label: "Toggle Board / Parchment ground",
              shortcut: "⌘T",
            },
          ]}
        />
        <Drawer
          open={drawerOpen}
          kicker="SPAN · 0x9F24A"
          title="envoy.ingress.tls_handshake"
          onDismiss={() => setDrawerOpen(false)}
        >
          <p className="dim">
            Upstream TLS termination completed in 4.2ms on control-plane-01.
          </p>
        </Drawer>
      </div>
    );
  },
};
