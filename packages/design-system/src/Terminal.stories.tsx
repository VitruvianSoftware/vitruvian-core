import type { Meta, StoryObj } from "@storybook/react-vite";
import { Terminal, Code } from "./Terminal";

const terminalMeta: Meta<typeof Terminal> = {
  title: "Components/Terminal",
  component: Terminal,
  parameters: { layout: "padded" },
};
export default terminalMeta;

export const Transcript: StoryObj<typeof Terminal> = {
  args: {
    title: "devx — zsh",
    cursor: true,
    lines: [
      { kind: "cmd", text: "brew tap vitruviansoftware/tap" },
      {
        kind: "out",
        text: "==> Tapping vitruviansoftware/tap\nTapped 3 formulae.",
      },
      { kind: "cmd", text: "devx cluster init --nodes 3" },
      { kind: "ok", text: "✓ vz vm provisioned        1.8s" },
      { kind: "ok", text: "✓ k3s control-plane up     6.2s" },
      { kind: "warn", text: "! node edge-03 drifted     reconcile queued" },
      { kind: "err", text: "✗ registry auth failed     exit 13" },
    ],
  },
};

export const InstallBlock: StoryObj<typeof Terminal> = {
  args: {
    framed: false,
    lines: [{ kind: "cmd", text: "brew install devx homelab" }],
  },
};

export const Source: StoryObj = {
  render: () => (
    <Code>
      <span className="c-com">
        {"// packages/design-system/src/vitruvian.css"}
      </span>
      {"\n"}
      <span className="c-key">@theme</span>
      {" {\n  --spacing-4: "}
      <span className="c-str">13px</span>
      {"; "}
      <span className="c-com">{"/* Fibonacci */"}</span>
      {"\n}"}
    </Code>
  ),
};
