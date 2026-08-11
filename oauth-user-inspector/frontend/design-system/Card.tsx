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

// `title` is widened from the DOM's tooltip string to a ReactNode heading, so
// the intrinsic attribute is omitted rather than (incompatibly) narrowed.
export interface CardProps extends Omit<
  React.HTMLAttributes<HTMLElement>,
  "title"
> {
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
