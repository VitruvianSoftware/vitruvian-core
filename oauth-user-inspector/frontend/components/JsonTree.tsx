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

import React, { useState } from "react";

interface JsonTreeProps {
  data: any;
  level?: number;
  path?: string;
}

const INDENT = "  ";

const isObject = (v: any) => v && typeof v === "object" && !Array.isArray(v);

const JsonNode: React.FC<JsonTreeProps> = ({ data, level = 0, path = "" }) => {
  const [open, setOpen] = useState(level < 2); // auto-expand top 2 levels

  if (!isObject(data) && !Array.isArray(data)) {
    return <span className="text-amber-200">{JSON.stringify(data)}</span>;
  }

  const entries = Array.isArray(data)
    ? data.map((v, i) => [i, v])
    : Object.entries(data);
  const isEmpty = entries.length === 0;

  return (
    <div className="font-mono text-[11px] leading-relaxed">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="mr-1 text-xs text-blue-300 hover:text-blue-200"
        title={open ? "Collapse" : "Expand"}
      >
        {open ? "−" : "+"}
      </button>
      <span className="text-slate-400">
        {Array.isArray(data) ? "Array" : "Object"}
      </span>
      <span className="text-slate-500 ml-1">[{entries.length}]</span>
      {open && !isEmpty && (
        <div className="ml-4 border-l border-slate-700 pl-3 mt-1 space-y-0.5">
          {entries.map(([k, v]: any) => {
            const childPath = path ? `${path}.${k}` : String(k);
            return (
              <div key={k} className="group">
                <span className="text-slate-500 select-none">{k}:</span>{" "}
                {isObject(v) || Array.isArray(v) ? (
                  <JsonNode data={v} level={level + 1} path={childPath} />
                ) : (
                  <span className="text-emerald-200">{JSON.stringify(v)}</span>
                )}
                <button
                  onClick={() =>
                    navigator.clipboard.writeText(
                      String(isObject(v) ? JSON.stringify(v) : v),
                    )
                  }
                  className="opacity-0 group-hover:opacity-100 transition-opacity ml-2 text-[10px] px-1 py-0.5 rounded bg-slate-700/60 text-slate-300 border border-slate-600 hover:bg-slate-600"
                  title="Copy value"
                >
                  copy
                </button>
              </div>
            );
          })}
        </div>
      )}
      {open && isEmpty && <span className="text-slate-500 ml-2">(empty)</span>}
    </div>
  );
};

const JsonTree: React.FC<{ data: any }> = ({ data }) => {
  const [expandAllToggle, setExpandAllToggle] = useState<number>(0);
  const [copied, setCopied] = useState(false);

  const handleCopyAll = async () => {
    await navigator.clipboard.writeText(JSON.stringify(data, null, 2));
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div>
      <div className="flex items-center gap-2 mb-2">
        <button
          className="text-[11px] px-2 py-1 rounded border border-slate-600 text-slate-300 hover:bg-slate-700"
          onClick={() => setExpandAllToggle((v) => v + 1)}
          title="Expand all"
        >
          Expand/Collapse
        </button>
        <button
          className="text-[11px] px-2 py-1 rounded border border-slate-600 text-slate-300 hover:bg-slate-700"
          onClick={handleCopyAll}
          title="Copy JSON"
        >
          {copied ? "Copied" : "Copy all"}
        </button>
      </div>
      {/* re-mount node to reset open state on toggle */}
      <div key={expandAllToggle}>
        <JsonNode data={data} />
      </div>
    </div>
  );
};

export default JsonTree;
