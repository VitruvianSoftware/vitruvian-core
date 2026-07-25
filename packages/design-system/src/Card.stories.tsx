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
import { Card } from "./Card.js";
import { Tag } from "./Tag.js";

const cardMeta: Meta<typeof Card> = {
  title: "Components/Card",
  component: Card,
  parameters: { layout: "padded" },
  args: {
    kicker: "01 · project",
    title: "DevX Protocol",
    children:
      "Standardise repository initialisation. Docker-tethered sandboxes and git-flow hooks eradicate configuration drift.",
    meta: "go · MIT",
  },
  argTypes: {
    surface: { control: "inline-radio", options: ["plate", "fill", "glass"] },
    elevation: { control: "inline-radio", options: [false, "sm", "md", "lg"] },
  },
};
export default cardMeta;
type Story = StoryObj<typeof Card>;

export const Default: Story = {};

export const Grid: Story = {
  render: () => (
    <div className="grid grid-cols-3 gap-5">
      <Card kicker="01 · project" title="DevX Protocol" meta="go · MIT">
        Docker-tethered sandboxes and git-flow hooks eradicate configuration
        drift.
      </Card>
      <Card kicker="02 · project" title="Homelab" meta="go · MIT">
        Automated provisioning for multi-node K3s edge clusters over bare metal
        via Lima VZ.
      </Card>
      <Card kicker="03 · project" title="NexusAgent" meta="swift · MIT">
        Local-first macOS assistant executing infrastructure commands over a
        secured gateway.
      </Card>
    </div>
  ),
};

export const Surfaces: Story = {
  render: () => (
    <div className="grid grid-cols-3 gap-5">
      <Card surface="plate" kicker="default" title=".plate">
        The line drawing. Use this unless you have a reason not to.
      </Card>
      <Card surface="fill" kicker="exception" title=".card-fill">
        A surface fill for dense rows and nested panels.
      </Card>
      <Card surface="glass" elevation="md" kicker="exception" title=".glass">
        Frosted — popovers and sticky summaries only.
      </Card>
    </div>
  ),
};

export const WithTags: Story = {
  render: () => (
    <Card
      kicker="Field note"
      title="Deterministic container orchestration, locally"
      meta={
        <>
          <Tag tone="accent">k3s</Tag>
          <Tag tone="outline">lima</Tag>
        </>
      }
    >
      One plate, one border. The frame is never doubled.
    </Card>
  ),
};
