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
import { EmptyState, Skeleton, Spinner } from "./States.js";
import { Button } from "./Button.js";
import { Plate } from "./Plate.js";
import { Label } from "./Tag.js";

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
