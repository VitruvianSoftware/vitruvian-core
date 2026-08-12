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
function Card({ children, ...props }) {
  return h("div", props, children);
}
function Plate({ children, ...props }) {
  return h("div", props, children);
}
function Tag({ children, ...props }) {
  return h("span", props, children);
}
function Spinner() {
  return h("div", { "aria-label": "Loading" });
}
function Skeleton() {
  return h("div", null);
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
  Spinner,
  Skeleton,
  cn,
};
