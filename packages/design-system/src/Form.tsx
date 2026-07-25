import * as React from "react";
import { cn } from "./cn";

export interface FieldProps {
  label: React.ReactNode;
  hint?: React.ReactNode;
  error?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

/** Mono label above, native control inside, sanguine error below. */
export function Field({ label, hint, error, children, className }: FieldProps) {
  return (
    <div className={cn("field", className)}>
      <label>{label}</label>
      {children}
      {hint && !error ? <div className="field-hint">{hint}</div> : null}
      {error ? <div className="field-error">↳ {error}</div> : null}
    </div>
  );
}

export const Input = React.forwardRef<
  HTMLInputElement,
  React.InputHTMLAttributes<HTMLInputElement>
>(function Input({ className, ...rest }, ref) {
  return <input ref={ref} className={cn("input", className)} {...rest} />;
});

export const Textarea = React.forwardRef<
  HTMLTextAreaElement,
  React.TextareaHTMLAttributes<HTMLTextAreaElement>
>(function Textarea({ className, ...rest }, ref) {
  return <textarea ref={ref} className={cn("input", className)} {...rest} />;
});

export const Select = React.forwardRef<
  HTMLSelectElement,
  React.SelectHTMLAttributes<HTMLSelectElement>
>(function Select({ className, children, ...rest }, ref) {
  return (
    <span className="select">
      <select ref={ref} className={cn("input", className)} {...rest}>
        {children}
      </select>
    </span>
  );
});

export function Checkbox({
  label,
  ...rest
}: { label: React.ReactNode } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="check">
      <input type="checkbox" {...rest} />
      <span className="box" />
      {label}
    </label>
  );
}

export function Radio({
  label,
  ...rest
}: { label: React.ReactNode } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="radio">
      <input type="radio" {...rest} />
      <span className="dot" />
      {label}
    </label>
  );
}

export function Switch({
  label,
  ...rest
}: { label: React.ReactNode } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="switch">
      <input type="checkbox" {...rest} />
      <span className="track" />
      {label}
    </label>
  );
}

export interface SegmentedProps {
  name: string;
  options: Array<{ value: string; label: React.ReactNode }>;
  value?: string;
  onValueChange?: (value: string) => void;
}

export function Segmented({
  name,
  options,
  value,
  onValueChange,
}: SegmentedProps) {
  return (
    <div className="seg" role="radiogroup">
      {options.map((o) => (
        <label className="seg-opt" key={o.value}>
          <input
            type="radio"
            name={name}
            value={o.value}
            checked={value === o.value}
            onChange={() => onValueChange?.(o.value)}
          />
          {o.label}
        </label>
      ))}
    </div>
  );
}
