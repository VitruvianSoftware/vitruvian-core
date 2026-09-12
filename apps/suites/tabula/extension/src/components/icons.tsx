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

/**
 * Material Icons component for consistent icon usage
 * Uses Google Material Icons font
 */

import React from "react";

interface IconProps {
  name: string;
  size?: "sm" | "md" | "lg";
  outlined?: boolean;
  className?: string;
  style?: React.CSSProperties;
}

/**
 * Material Icon wrapper component
 * @param name - Icon name (e.g., 'add', 'search', 'more_vert')
 * @param size - Optional size: 'sm' (16px), 'md' (18px), 'lg' (24px)
 * @param outlined - Use outlined variant
 * @param className - Additional CSS classes
 */
export const Icon: React.FC<IconProps> = ({
  name,
  size = "md",
  outlined = false,
  className = "",
  style,
}) => {
  const sizeClass = size !== "md" ? `icon-${size}` : "";
  const baseClass = outlined ? "material-icons-outlined" : "material-icons";

  return (
    <i
      className={`${baseClass} ${sizeClass} ${className}`.trim()}
      style={style}
    >
      {name}
    </i>
  );
};

/**
 * Common icon presets for consistent usage
 */
export const Icons = {
  // Navigation
  ChevronDown: (props?: Partial<IconProps>) => (
    <Icon name="keyboard_arrow_down" size="sm" {...props} />
  ),
  ChevronRight: (props?: Partial<IconProps>) => (
    <Icon name="keyboard_arrow_right" size="sm" {...props} />
  ),
  ChevronUp: (props?: Partial<IconProps>) => (
    <Icon name="keyboard_arrow_up" size="sm" {...props} />
  ),

  // Actions
  Add: (props?: Partial<IconProps>) => <Icon name="add" {...props} />,
  Edit: (props?: Partial<IconProps>) => (
    <Icon name="edit" outlined {...props} />
  ),
  Delete: (props?: Partial<IconProps>) => (
    <Icon name="delete" outlined {...props} />
  ),
  Close: (props?: Partial<IconProps>) => <Icon name="close" {...props} />,
  MoreVert: (props?: Partial<IconProps>) => (
    <Icon name="more_vert" {...props} />
  ),
  MoreHoriz: (props?: Partial<IconProps>) => (
    <Icon name="more_horiz" {...props} />
  ),

  // UI
  Search: (props?: Partial<IconProps>) => <Icon name="search" {...props} />,
  Link: (props?: Partial<IconProps>) => <Icon name="link" {...props} />,
  OpenInNew: (props?: Partial<IconProps>) => (
    <Icon name="open_in_new" outlined {...props} />
  ),
  ContentCopy: (props?: Partial<IconProps>) => (
    <Icon name="content_copy" outlined {...props} />
  ),

  // Status
  Check: (props?: Partial<IconProps>) => <Icon name="check" {...props} />,
  CheckCircle: (props?: Partial<IconProps>) => (
    <Icon name="check_circle" outlined {...props} />
  ),

  // Workspace/Navigation
  Folder: (props?: Partial<IconProps>) => (
    <Icon name="folder" outlined {...props} />
  ),
  Dashboard: (props?: Partial<IconProps>) => (
    <Icon name="dashboard" outlined {...props} />
  ),
  Tab: (props?: Partial<IconProps>) => <Icon name="tab" outlined {...props} />,
  Note: (props?: Partial<IconProps>) => (
    <Icon name="description" outlined {...props} />
  ),
  Task: (props?: Partial<IconProps>) => (
    <Icon name="check_box" outlined {...props} />
  ),
} as const;

export default Icon;
