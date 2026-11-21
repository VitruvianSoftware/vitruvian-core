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
import { Plate } from "./Plate.js";
import { Button } from "./Button.js";
import { Label } from "./Tag.js";
import { Meter, Status, LogStream } from "./DataDisplay.js";
import { Tabs } from "./Nav.js";

const motionMeta: Meta = {
  title: "Foundations/Motion",
  parameters: { layout: "padded" },
};
export default motionMeta;

export const Marks: StoryObj = {
  name: "Registration marks",
  render: function Render() {
    const [key, setKey] = React.useState(0);
    return (
      <div className="grid grid-cols-2 gap-5">
        <Plate live className="card">
          <div className="card-kicker">live</div>
          <h4 className="card-title">Sharpen on approach</h4>
          <p className="card-body">
            Marks sit at 40% until hover or focus-within, then snap sharp.
          </p>
        </Plate>
        <Plate enter key={key} className="card">
          <div className="card-kicker">enter</div>
          <h4 className="card-title">Draw in clockwise</h4>
          <p className="card-body">
            Four crosses, 60ms apart. Once per view, on the thing that just
            appeared.
          </p>
          <Button size="sm" onClick={() => setKey((k) => k + 1)}>
            Replay
          </Button>
        </Plate>
      </div>
    );
  },
};

export const PressAndConfirm: StoryObj = {
  render: function Render() {
    const [done, setDone] = React.useState(false);
    return (
      <div className="flex items-center gap-4">
        <Button
          variant="primary"
          done={done}
          onClick={() => {
            setDone(true);
            window.setTimeout(() => setDone(false), 1400);
          }}
        >
          {done ? "Applied" : "Apply"}
        </Button>
        <span className="text-sm text-paper-dim">
          1px of travel on press; a completed action flips to the ok tint for a
          beat.
        </span>
      </div>
    );
  },
};

export const MeasuredChange: StoryObj = {
  render: function Render() {
    const [v, setV] = React.useState(0.31);
    const tone = v > 0.9 ? "crit" : v > 0.75 ? "warn" : undefined;
    return (
      <Plate className="card max-w-[420px]">
        <div className="flex justify-between">
          <Label>Disk</Label>
          <span className="mono text-[11px]">{Math.round(v * 100)}%</span>
        </div>
        <Meter value={v} tone={tone} />
        <div className="flex gap-4 mt-3">
          {[0.31, 0.81, 0.96].map((n) => (
            <Button size="sm" key={n} onClick={() => setV(n)}>
              {Math.round(n * 100)}%
            </Button>
          ))}
        </div>
      </Plate>
    );
  },
};

export const Indicators: StoryObj = {
  render: function Render() {
    const [tab, setTab] = React.useState("nodes");
    return (
      <Tabs
        active={tab}
        onChange={setTab}
        tabs={[
          { id: "nodes", label: "Nodes" },
          { id: "workloads", label: "Workloads" },
          { id: "events", label: "Events" },
        ]}
      />
    );
  },
};

export const LiveSignals: StoryObj = {
  render: function Render() {
    const [rows, setRows] = React.useState<
      Array<{
        ts: string;
        level: "ok" | "info" | "warn" | "err";
        message: string;
        isNew?: boolean;
      }>
    >([]);
    React.useEffect(() => {
      const feed = [
        { level: "ok", message: "node edge-01 ready" },
        { level: "info", message: "pulumi preview: 2 to update" },
        { level: "warn", message: "edge-03 kubelet drift" },
        { level: "err", message: "registry auth failed — exit 13" },
      ] as const;
      let n = 0;
      const id = window.setInterval(() => {
        const item = feed[n % feed.length]!;
        n += 1;
        const ts = new Date().toTimeString().slice(0, 8);
        setRows((prev) => [{ ...item, ts, isNew: true }, ...prev].slice(0, 5));
      }, 1800);
      return () => window.clearInterval(id);
    }, []);
    return (
      <div className="flex flex-col gap-5">
        <div className="flex gap-6">
          <Status signal="run">reconciling</Status>
          <Status signal="crit">unreachable</Status>
          <span className="text-sm text-paper-dim">
            Only running breathes. Criticality holds still.
          </span>
        </div>
        <Plate className="card">
          <LogStream rows={rows} />
        </Plate>
      </div>
    );
  },
};
