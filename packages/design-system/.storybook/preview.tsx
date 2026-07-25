import * as React from "react";
import type { Preview, Decorator } from "@storybook/react-vite";
import "../src/vitruvian.css";

/* The board is the default; parchment is the alternate. The toolbar switch
   writes data-theme on <html> exactly as a consuming app would. */
const withTheme: Decorator = (Story, ctx) => {
  const theme = ctx.globals.theme === "light" ? "light" : "dark";
  React.useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.body.style.background = "var(--color-bg)";
    document.body.style.color = "var(--color-text)";
  }, [theme]);
  return (
    <div
      data-theme={theme}
      style={{
        background: "var(--color-bg)",
        color: "var(--color-text)",
        padding: 21,
      }}
    >
      <Story />
    </div>
  );
};

const preview: Preview = {
  decorators: [withTheme],
  initialGlobals: { theme: "dark" },
  globalTypes: {
    theme: {
      description: "Ground",
      toolbar: {
        title: "Ground",
        icon: "contrast",
        items: [
          { value: "dark", title: "Board (dark)" },
          { value: "light", title: "Parchment (light)" },
        ],
        dynamicTitle: true,
      },
    },
  },
  parameters: {
    layout: "fullscreen",
    controls: { expanded: true },
    options: {
      storySort: {
        order: ["Foundations", "Components", "Patterns"],
      },
    },
  },
};

export default preview;
