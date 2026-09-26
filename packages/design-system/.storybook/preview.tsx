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
import type { Preview, Decorator } from "@storybook/react-vite";
import { MINIMAL_VIEWPORTS } from "storybook/viewport";
import "../src/vitruvian.css";

/* The board is the default; parchment is the alternate. The toolbar switch
   writes data-theme on <html> exactly as a consuming app would.

   Fullscreen stories draw their own full-bleed page (background + min-height),
   so the 21px gutter must not wrap them: under the viewport switch that gutter
   comes straight out of the phone's width (a 320px iframe leaves 278px). */
const withTheme: Decorator = (Story, ctx) => {
  const theme = ctx.globals.theme === "light" ? "light" : "dark";
  const fullscreen = ctx.parameters?.layout === "fullscreen";
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
        padding: fullscreen ? 0 : 21,
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
    viewport: {
      /* Storybook's own presets are 320 (mobile1) and 414 (mobile2); the
         390 x 844 phone is the width the mobile shells are designed at. */
      options: {
        ...MINIMAL_VIEWPORTS,
        phone: {
          name: "Phone (390 x 844)",
          styles: { width: "390px", height: "844px" },
          type: "mobile",
        },
      },
    },
    options: {
      storySort: {
        order: ["Foundations", "Components", "Patterns"],
      },
    },
  },
};

export default preview;
