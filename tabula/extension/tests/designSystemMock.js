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

const React = require("react");

module.exports = {
  Button: (props) => React.createElement("button", props, props.children),
  Plate: (props) => React.createElement("div", props, props.children),
  Textarea: (props) => React.createElement("textarea", props),
  Input: (props) => React.createElement("input", props),
  Field: (props) =>
    React.createElement(
      "div",
      { className: props.className },
      props.label ? React.createElement("label", null, props.label) : null,
      props.children,
      props.hint ? React.createElement("div", null, props.hint) : null,
      props.error ? React.createElement("div", null, props.error) : null,
    ),
  Status: (props) => React.createElement("span", props, props.children),
  Tag: (props) => React.createElement("span", props, props.children),
  EmptyState: (props) =>
    React.createElement(
      "div",
      { className: props.className },
      props.mark ? React.createElement("div", null, props.mark) : null,
      props.title ? React.createElement("h4", null, props.title) : null,
      props.children ? React.createElement("p", null, props.children) : null,
      props.actions ? React.createElement("div", null, props.actions) : null,
    ),
  Modal: (props) => React.createElement("div", props, props.children),
};
