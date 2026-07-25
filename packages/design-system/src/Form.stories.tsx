import * as React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import {
  Field,
  Input,
  Textarea,
  Select,
  Checkbox,
  Radio,
  Switch,
  Segmented,
} from "./Form";
import { Button } from "./Button";

const formMeta: Meta = {
  title: "Components/Form",
  parameters: { layout: "padded" },
};
export default formMeta;

export const Fields: StoryObj = {
  render: () => (
    <div className="grid grid-cols-2 gap-5 max-w-[720px]">
      <Field label="Project name">
        <Input defaultValue="nexus-agent" />
      </Field>
      <Field label="Region">
        <Select defaultValue="us-central1">
          <option>us-central1</option>
          <option>europe-west4</option>
          <option>asia-southeast1</option>
        </Select>
      </Field>
      <Field label="Service account" error="principal lacks roles/run.admin">
        <Input defaultValue="deployer@vitruvian" aria-invalid="true" />
      </Field>
      <Field label="Search">
        <Input type="search" placeholder="Filter workloads…" />
      </Field>
      <div className="col-span-2">
        <Field
          label="Change note"
          hint="Recorded on the audit trail. Markdown is not rendered."
        >
          <Textarea placeholder="Why is this being applied?" />
        </Field>
      </div>
    </div>
  ),
};

export const Choices: StoryObj = {
  render: () => (
    <div className="grid grid-cols-2 gap-5 max-w-[720px]">
      <div className="flex flex-col gap-3">
        <Radio name="strategy" label="Blue-green" defaultChecked />
        <Radio name="strategy" label="Rolling" />
        <Radio name="strategy" label="Recreate" />
      </div>
      <div className="flex flex-col gap-3">
        <Checkbox label="Run smoke suite" defaultChecked />
        <Checkbox label="Skip drift detection" />
        <Switch label="Require approval" defaultChecked />
        <Switch label="Break-glass mode" />
      </div>
    </div>
  ),
};

export const SegmentedControl: StoryObj = {
  render: function Render() {
    const [env, setEnv] = React.useState("dev");
    return (
      <div className="flex flex-col gap-5 items-start">
        <Segmented
          name="env"
          value={env}
          onValueChange={setEnv}
          options={[
            { value: "dev", label: "dev" },
            { value: "nonprod", label: "nonprod" },
            { value: "prod", label: "prod" },
          ]}
        />
        <div className="flex gap-3">
          <Button variant="ghost">Cancel</Button>
          <Button variant="primary">Apply to {env}</Button>
        </div>
      </div>
    );
  },
};
