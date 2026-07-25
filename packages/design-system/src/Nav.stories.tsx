import * as React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Nav, Tabs, Shell, SideGroup, SideItem, Crumbs } from "./Nav";
import { Button } from "./Button";
import { Status } from "./DataDisplay";
import { Plate } from "./Plate";

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
