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
import { Tag, Label, Kbd } from "./Tag.js";

const tagMeta: Meta<typeof Tag> = {
  title: "Components/Tag",
  component: Tag,
  parameters: { layout: "padded" },
};
export default tagMeta;

export const Tones: StoryObj = {
  render: () => (
    <div className="flex flex-wrap items-center gap-4">
      <Tag tone="accent">v0.1.22</Tag>
      <Tag tone="outline">draft</Tag>
      <Tag tone="neutral">internal</Tag>
      <Tag tone="ok">passing</Tag>
      <Tag tone="warn">degraded</Tag>
      <Tag tone="sanguine">breaking</Tag>
    </div>
  ),
};

export const Labels: StoryObj = {
  render: () => (
    <div className="flex flex-col gap-3">
      <Label>section label</Label>
      <Label accent>steel label</Label>
      <div className="flex items-center gap-3">
        <Kbd>⌘</Kbd>
        <Kbd>K</Kbd>
        <span className="text-sm text-paper-dim">
          opens the command palette
        </span>
      </div>
    </div>
  ),
};
