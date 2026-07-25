import * as React from "react";
import { cn } from "./cn";
import { RegistrationMarks } from "./Plate";

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
