import type { Meta, StoryObj } from "@storybook/react-vite";
import { Tag, Label, Kbd } from "./Tag";

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
