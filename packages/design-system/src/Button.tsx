import * as React from "react";
import { cn } from "./cn";
import { RegistrationMarks } from "./Plate";

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: "sm" | "md";
  /** Square icon-only button. Requires aria-label. */
  icon?: boolean;
  block?: boolean;
  /** The page's single most important action wears the registration marks. */
  registered?: boolean;
  /** Completed — flips to the ok tint for a beat instead of raising a toast. */
  done?: boolean;
}

/**
 * Actions speak in the mono voice — uppercase, tracked, 12px. Exactly one
 * solid steel primary per view; everything else is outline or ghost.
 */
export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  function Button(
    {
      variant = "secondary",
      size = "md",
      icon,
      block,
      registered,
      done,
      className,
      children,
      type = "button",
      ...rest
    },
    ref,
  ) {
    return (
      <button
        ref={ref}
        type={type}
        className={cn(
          "btn",
          `btn-${variant}`,
          size === "sm" && "btn-sm",
          icon && "btn-icon",
          block && "btn-block",
          registered && "plate",
          done && "is-done",
          className,
        )}
        {...rest}
      >
        {registered ? <RegistrationMarks /> : null}
        {children}
      </button>
    );
  },
);
