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
import { cn } from "./cn.js";
import { RegistrationMarks } from "./Plate.js";

export type TermLine =
  | { kind: "cmd"; text: string }
  | { kind: "out"; text: string }
  | { kind: "ok" | "warn" | "err"; text: string };

/**
 * A command transcript. Keeps the ink ground in both themes — a terminal is a
 * terminal. Prompt, outcome markers and comments are the only colour.
 */
export function Terminal({
  title,
  lines,
  framed = true,
  cursor,
}: {
  title?: React.ReactNode;
  lines: TermLine[];
  framed?: boolean;
  cursor?: boolean;
}) {
  return (
    <div className={cn("term", framed && "plate")}>
      {framed ? <RegistrationMarks /> : null}
      {title ? <div className="term-bar">{title}</div> : null}
      <div className="term-body">
        {lines.map((l, i) =>
          l.kind === "cmd" ? (
            <div className="term-line" key={i}>
              {l.text}
            </div>
          ) : (
            <div
              className={cn("term-out", l.kind !== "out" && `term-${l.kind}`)}
              key={i}
            >
              {l.text}
            </div>
          ),
        )}
        {cursor ? (
          <div className="term-line">
            <span className="term-cursor" />
          </div>
        ) : null}
      </div>
    </div>
  );
}

export function Code({
  className,
  ...rest
}: React.HTMLAttributes<HTMLPreElement>) {
  return <pre className={cn("code", className)} {...rest} />;
}
