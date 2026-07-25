import * as React from "react";
import { cn } from "./cn";
import { RegistrationMarks } from "./Plate";

export interface CardProps extends React.HTMLAttributes<HTMLElement> {
  kicker?: React.ReactNode;
  title?: React.ReactNode;
  meta?: React.ReactNode;
  /** 'plate' is the default line drawing; the others are documented exceptions. */
  surface?: "plate" | "fill" | "glass";
  elevation?: false | "sm" | "md" | "lg";
}

/** A card is a plate with a kicker, a mono title and Plex Sans body copy. */
export function Card({
  kicker,
  title,
  meta,
  surface = "plate",
  elevation = false,
  className,
  children,
  ...rest
}: CardProps) {
  return (
    <article
      className={cn(
        "card",
        surface === "plate" && "plate",
        surface === "fill" && "card-fill",
        surface === "glass" && "glass",
        elevation && `elev-${elevation}`,
        className,
      )}
      {...rest}
    >
      {surface === "plate" ? <RegistrationMarks /> : null}
      {kicker ? <div className="card-kicker">{kicker}</div> : null}
      {title ? <h3 className="card-title">{title}</h3> : null}
      {children ? <p className="card-body">{children}</p> : null}
      {meta ? <div className="card-meta">{meta}</div> : null}
    </article>
  );
}
