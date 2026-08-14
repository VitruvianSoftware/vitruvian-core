const React = require("react");

module.exports = {
  Button: (props) => React.createElement("button", props, props.children),
  Plate: (props) => React.createElement("div", props, props.children),
  Textarea: (props) => React.createElement("textarea", props),
  EmptyState: (props) => React.createElement("div", props, props.children),
  Modal: (props) => React.createElement("div", props, props.children),
};
