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
import { ListItem, AutoGrid, KeyValue, Accordion } from "./Layout.js";
import { VIcon, VitruvianIcons, type VitruvianIconName } from "./Icons.js";
import { Plate } from "./Plate.js";
import { Tag } from "./Tag.js";
import { CopyButton } from "./Form.js";

const layoutMeta: Meta = {
  title: "Components/Lists, ledger & icons",
  parameters: { layout: "padded" },
};
export default layoutMeta;

export const ListRows: StoryObj = {
  render: function Render() {
    const [selected, setSelected] = React.useState("cp-01");
    return (
      <Plate className="max-w-[560px]">
        <ListItem
          status="ok"
          title="control-plane-01"
          subtitle="100.64.0.11 · k3s v1.32.4+k3s1"
          selected={selected === "cp-01"}
          onClick={() => setSelected("cp-01")}
          trailing={<Tag tone="ok">READY</Tag>}
        />
        <ListItem
          status="run"
          title="worker-gpu-02"
          subtitle="100.64.0.22 · reconciling daemonsets"
          selected={selected === "gpu-02"}
          onClick={() => setSelected("gpu-02")}
          trailing={<Tag tone="accent">SYNCING</Tag>}
        />
        <ListItem
          status="warn"
          title="edge-gateway-03"
          subtitle="100.64.0.34 · certificate renewal pending"
          selected={selected === "edge-03"}
          onClick={() => setSelected("edge-03")}
          trailing={<Tag tone="warn">DRIFT</Tag>}
        />
      </Plate>
    );
  },
};

export const KeyValueLedgerAndAccordion: StoryObj = {
  render: () => (
    <div className="grid grid-cols-2 gap-6">
      <Plate className="card">
        <div className="card-kicker">OIDC ID TOKEN CLAIMS</div>
        <KeyValue
          items={[
            { key: "iss", value: "https://auth.vitruvian.dev" },
            {
              key: "sub",
              value: "usr_01J9X7K2M8P4Q6R",
              action: <CopyButton value="usr_01J9X7K2M8P4Q6R" />,
            },
            { key: "aud", value: "tabula-web-client" },
            { key: "amr", value: "hwk · mfa · passkey" },
          ]}
        />
      </Plate>
      <Plate className="card">
        <div className="card-kicker">SPECIFICATION SECTIONS</div>
        <Accordion
          defaultOpenIds={["net"]}
          items={[
            {
              id: "net",
              title: "Cilium eBPF Datapath",
              meta: "L3/L4",
              content:
                "Kube-proxy replacement running in strict native routing mode over WireGuard tailnet links.",
            },
            {
              id: "sec",
              title: "Sealed Secrets Controller",
              meta: "RSA-OAEP",
              content:
                "Asymmetric cluster key pair rotated every 30 days; manifests encrypted offline via kubeseal.",
            },
            {
              id: "obs",
              title: "Thanos + Tempo Telemetry",
              meta: "OTLP",
              content:
                "Metrics compacted to R2 object storage; distributed traces sampled at 10% tail-based.",
            },
          ]}
        />
      </Plate>
    </div>
  ),
};

export const IconCatalog: StoryObj = {
  render: () => {
    const names = Object.keys(VitruvianIcons) as VitruvianIconName[];
    return (
      <AutoGrid minWidth={140}>
        {names.map((name) => (
          <Plate
            key={name}
            marks={false}
            className="p-4 flex items-center gap-3"
          >
            <VIcon icon={name} size={18} className="text-steel-text" />
            <span className="mono text-xs dim">{name}</span>
          </Plate>
        ))}
      </AutoGrid>
    );
  },
};
