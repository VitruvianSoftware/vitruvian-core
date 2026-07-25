import type { Meta, StoryObj } from "@storybook/react-vite";
import { EmptyState, Skeleton, Spinner } from "./States";
import { Button } from "./Button";
import { Plate } from "./Plate";
import { Label } from "./Tag";

const statesMeta: Meta = {
  title: "Components/Empty, loading, error",
  parameters: { layout: "padded" },
};
export default statesMeta;

export const Empty: StoryObj = {
  render: () => (
    <EmptyState
      title="No workspaces yet"
      actions={
        <div className="flex gap-4">
          <Button size="sm" variant="primary">
            New workspace
          </Button>
          <Button size="sm">Import</Button>
        </div>
      }
    >
      Workspaces group tabs, tasks and documents. Create one, or import from an
      existing session.
    </EmptyState>
  ),
};

export const Loading: StoryObj = {
  render: () => (
    <Plate className="card">
      <div className="flex items-center gap-4">
        <Spinner />
        <Label>Reconciling cluster state</Label>
      </div>
      <div className="flex flex-col gap-3 mt-3">
        <Skeleton width="70%" />
        <Skeleton width="90%" />
        <Skeleton width="52%" />
      </div>
    </Plate>
  ),
};

export const Failure: StoryObj = {
  render: () => (
    <EmptyState
      framed
      title="The gateway did not answer"
      actions={
        <div className="flex gap-4">
          <Button size="sm">Retry</Button>
          <Button size="sm" variant="ghost">
            Status page
          </Button>
        </div>
      }
    >
      The request reached the edge but the upstream Cloud Run revision returned
      no response. This is almost always a cold-start timeout during a
      blue-green shift.
    </EmptyState>
  ),
};
