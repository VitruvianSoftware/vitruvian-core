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
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Terminal, Code } from "./Terminal.js";

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
