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
import * as React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Nav, Tabs, Shell, SideGroup, SideItem, Crumbs } from "./Nav.js";
import { Button } from "./Button.js";
import { Status } from "./DataDisplay.js";
import { Plate } from "./Plate.js";

const navMeta: Meta = {
  title: "Components/Navigation",
  parameters: { layout: "padded" },
};
export default navMeta;

export const Header: StoryObj = {
  render: () => (
    <Plate field="lg" className="pb-6">
      <Nav
        actions={
          <Button size="sm" variant="primary">
            GitHub
          </Button>
        }
      >
        <a href="#" aria-current="page">
          Projects
        </a>
        <a href="#">Stack</a>
        <a href="#">Docs</a>
        <a href="#">Blog</a>
      </Nav>
      <div className="p-5">
        <h3 className="m-0">Content scrolls under the glass.</h3>
      </div>
    </Plate>
  ),
};

export const ApplicationShell: StoryObj = {
  render: function Render() {
    const [tab, setTab] = React.useState("nodes");
    return (
      <Plate className="overflow-hidden">
        <Shell
          side={
            <>
              <SideGroup>Platform</SideGroup>
              <SideItem href="#" current>
                Overview
              </SideItem>
              <SideItem href="#">Clusters</SideItem>
              <SideItem href="#">Workloads</SideItem>
              <SideGroup>Delivery</SideGroup>
              <SideItem href="#">Pipelines</SideItem>
              <SideItem href="#">Releases</SideItem>
            </>
          }
        >
          <Crumbs>
            <a href="#">platform</a> / <a href="#">clusters</a> /{" "}
            <span className="dim">edge-01</span>
          </Crumbs>
          <h3 className="my-4">edge-01</h3>
          <Tabs
            active={tab}
            onChange={setTab}
            tabs={[
              { id: "nodes", label: "Nodes" },
              { id: "workloads", label: "Workloads" },
              { id: "events", label: "Events" },
              { id: "config", label: "Config" },
            ]}
          />
          <div className="flex gap-5 mt-5">
            <Status signal="ok">3/3 ready</Status>
            <Status signal="run">reconciling</Status>
          </div>
        </Shell>
      </Plate>
    );
  },
};
