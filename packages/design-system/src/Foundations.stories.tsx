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
import { Plate, Rule, VMark, Glass } from "./Plate.js";
import { Label } from "./Tag.js";

const foundationsMeta: Meta = {
  title: "Foundations/Overview",
  parameters: { layout: "padded" },
};
export default foundationsMeta;

const roles = [
  ["ink", "--color-bg", "#0e1317"],
  ["ink-2", "--color-surface", "#141b20"],
  ["ink-3", "--color-surface-2", "#1b2429"],
  ["paper", "--color-text", "#e7e4dd"],
  ["paper-dim", "--color-text-dim", "#9aa3a9"],
  ["steel", "--color-accent", "#5980a6"],
  ["steel-text", "--color-accent-text", "#93b0ca"],
  ["sanguine", "--color-sanguine", "#b4553c"],
  ["ok", "--color-ok", "#5b9c78"],
  ["warn", "--color-warn", "#c89a3c"],
] as const;

export const Color: StoryObj = {
  render: () => (
    <div className="grid grid-cols-5 gap-5">
      {roles.map(([name, token, hex]) => (
        <div key={name} className="flex flex-col gap-2">
          <div
            style={{
              height: 55,
              background: `var(${token})`,
              border: "1px solid var(--color-divider)",
            }}
          />
          <Label>{name}</Label>
          <span className="mono text-[11px] text-paper-dim">{hex}</span>
        </div>
      ))}
    </div>
  ),
};

export const Ramps: StoryObj = {
  render: () => (
    <div className="flex flex-col gap-6">
      {(["accent", "sanguine", "neutral"] as const).map((role) => (
        <div key={role}>
          <Label>{role}</Label>
          <div className="mt-3 grid grid-cols-9 gap-[2px]">
            {[100, 200, 300, 400, 500, 600, 700, 800, 900].map((step) => (
              <i
                key={step}
                style={{
                  height: 38,
                  background: `var(--color-${role}-${step})`,
                }}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  ),
};

export const Type: StoryObj = {
  render: () => (
    <div>
      <h1>Architecting platform infrastructure</h1>
      <h2>Deterministic by construction</h2>
      <h3>Reproducible environments</h3>
      <h4>Provisioning protocol</h4>
      <h6>Section label · h6</h6>
      <p style={{ fontSize: 17 }}>
        Lead paragraphs at 17px in IBM Plex Sans. Headings, buttons, labels and
        data are JetBrains Mono — the machine voice. The contrast between the
        two is the whole typographic idea.
      </p>
      <p>
        Body copy at 15px, line height 1.6, measure capped near 64 characters.
      </p>
      <Label>label · 10px / .16em / uppercase</Label>
    </div>
  ),
};

export const Space: StoryObj = {
  name: "Space (Fibonacci)",
  render: () => (
    <div className="flex flex-col gap-3">
      {[
        ["1", 3],
        ["2", 5],
        ["3", 8],
        ["4", 13],
        ["5", 21],
        ["6", 34],
        ["7", 55],
        ["8", 89],
      ].map(([n, px]) => (
        <div key={n as string} className="flex items-center gap-4">
          <Label>space-{n}</Label>
          <span className="mono text-[11px] text-paper-dim w-11 text-right">
            {px}px
          </span>
          <i
            style={{
              display: "block",
              height: 13,
              width: px as number,
              background: "var(--color-accent)",
            }}
          />
        </div>
      ))}
    </div>
  ),
};

export const Motifs: StoryObj = {
  render: () => (
    <div className="flex flex-col gap-5">
      <Plate className="p-5">
        <Label accent>.plate + registration marks</Label>
        <p className="m-0 mt-3 text-sm text-paper-dim">
          The default frame. One hairline, square corners, four crosshairs
          outside the box.
        </p>
      </Plate>
      <div className="flex items-center gap-6">
        <VMark size={64} className="text-steel-text" />
        <VMark size={34} />
        <VMark size={21} className="text-sanguine-text" />
        <Label>.vm — circle inscribed in square</Label>
      </div>
      <Rule marked />
      <Plate field="sm" className="p-6">
        <Glass className="p-5 shadow-md">
          <Label>.glass — elevation only</Label>
        </Glass>
      </Plate>
    </div>
  ),
};
