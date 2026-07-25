import * as React from "react";
import { cn } from "./cn";

export type TagTone =
  "accent" | "sanguine" | "neutral" | "outline" | "ok" | "warn";

/** Small mono label. Tone carries meaning, never decoration. */
export function Tag({
  tone = "neutral",
  className,
  ...rest
}: { tone?: TagTone } & React.HTMLAttributes<HTMLSpanElement>) {
  return <span className={cn("tag", `tag-${tone}`, className)} {...rest} />;
}

/** The annotation voice: 10px mono, tracked, uppercase, dim. */
export function Label({
  accent,
  className,
  ...rest
}: { accent?: boolean } & React.HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn("label", accent && "label-accent", className)}
      {...rest}
    />
  );
}

export function Kbd({ className, ...rest }: React.HTMLAttributes<HTMLElement>) {
  return <kbd className={cn("kbd", className)} {...rest} />;
}
