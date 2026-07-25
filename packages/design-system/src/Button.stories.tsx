import type { Meta, StoryObj } from "@storybook/react-vite";
import { Button } from "./Button";

const buttonMeta: Meta<typeof Button> = {
  title: "Components/Button",
  component: Button,
  parameters: { layout: "padded" },
  args: { children: "Deploy" },
  argTypes: {
    variant: {
      control: "inline-radio",
      options: ["primary", "secondary", "ghost", "danger"],
    },
    size: { control: "inline-radio", options: ["sm", "md"] },
  },
};
export default buttonMeta;
type Story = StoryObj<typeof Button>;

export const Primary: Story = { args: { variant: "primary" } };
export const Secondary: Story = { args: { variant: "secondary" } };
export const Ghost: Story = { args: { variant: "ghost", children: "Docs" } };
export const Danger: Story = {
  args: { variant: "danger", children: "Destroy" },
};

export const AllVariants: Story = {
  render: () => (
    <div className="flex flex-wrap items-center gap-4">
      <Button variant="primary">Deploy</Button>
      <Button variant="secondary">Preview plan</Button>
      <Button variant="ghost">Docs</Button>
      <Button variant="danger">Destroy</Button>
      <Button disabled>Locked</Button>
      <Button variant="primary" registered>
        Ship release
      </Button>
    </div>
  ),
};

export const Sizes: Story = {
  render: () => (
    <div className="flex flex-wrap items-center gap-4">
      <Button size="sm" variant="primary">
        Small
      </Button>
      <Button variant="primary">Default</Button>
      <Button icon aria-label="Add" variant="primary">
        +
      </Button>
    </div>
  ),
};

export const Block: Story = {
  args: { variant: "primary", block: true, children: "Provision cluster" },
};
