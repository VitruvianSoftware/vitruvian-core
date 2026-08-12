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

// Mock for @vitruviansoftware/design-system in jest tests. The real package
// requires Tailwind + CSS build pipeline that isn't available in jsdom. Each
// component renders its semantic HTML equivalent so tests can assert on
// behaviour (clicks, text content, form inputs) without the styling layer.
const React = require("react");
const h = React.createElement;

function Button({ children, ...props }) {
  return h("button", props, children);
}
function Field({ label, children, ...props }) {
  return h("div", props, label ? h("label", null, label) : null, children);
}
function Input(props) {
  return h("input", props);
}
function Textarea(props) {
  return h("textarea", props);
}
function Select({ children, ...props }) {
  return h("select", props, children);
}
function Checkbox(props) {
  return h("input", { type: "checkbox", ...props });
}
function Card({ kicker, title, meta, surface, elevation, children, ...props }) {
  return h(
    "article",
    props,
    kicker ? h("div", null, kicker) : null,
    title ? h("h3", null, title) : null,
    children ? h("p", null, children) : null,
    meta ? h("div", null, meta) : null,
  );
}
function Plate({ as, live, enter, marks, field, children, ...props }) {
  return h(as || "div", props, children);
}
function Tag({ children, ...props }) {
  return h("span", props, children);
}
function Tabs({ tabs, active, onChange }) {
  return h(
    "div",
    { role: "tablist" },
    tabs.map(function (t) {
      return h(
        "button",
        {
          key: t.id,
          role: "tab",
          "aria-selected": t.id === active,
          onClick: function () {
            return onChange(t.id);
          },
        },
        t.label,
      );
    }),
  );
}
function EmptyState({ title, children, actions }) {
  return h(
    "div",
    null,
    h("h4", null, title),
    children ? h("p", null, children) : null,
    actions || null,
  );
}
function Nav({ brand, children, actions }) {
  return h("nav", null, brand, children, actions);
}
function Shell({ side, children }) {
  return h("div", null, h("aside", null, side), h("section", null, children));
}
function SideGroup({ children }) {
  return h("div", null, children);
}
function SideItem({ children, ...props }) {
  return h("a", props, children);
}
function Crumbs({ children }) {
  return h("div", null, children);
}
function Spinner() {
  return h("span", { role: "status", "aria-label": "Loading" });
}
function Skeleton({ width, height, className }) {
  return h("span", {
    className: ["skeleton", className].filter(Boolean).join(" "),
    style: { display: "block", width: width, height: height },
  });
}
function VMark() {
  return h("span", { "aria-hidden": true });
}
function RegistrationMarks() {
  return null;
}
function Rule() {
  return h("hr", null);
}
function Glass({ children, ...props }) {
  return h("div", props, children);
}
function cn(...args) {
  return args.filter(Boolean).join(" ");
}

module.exports = {
  Button,
  Field,
  Input,
  Textarea,
  Select,
  Checkbox,
  Card,
  Plate,
  Tag,
  Tabs,
  Nav,
  Shell,
  SideGroup,
  SideItem,
  Crumbs,
  Spinner,
  Skeleton,
  EmptyState,
  VMark,
  RegistrationMarks,
  Rule,
  Glass,
  cn,
};
