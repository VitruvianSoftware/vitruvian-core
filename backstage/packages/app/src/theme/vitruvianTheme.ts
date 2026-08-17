// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import { createUnifiedTheme, genPageTheme, palettes, shapes } from "@backstage/theme";

// Vitruvian Design System Tokens
const vitruvianDarkPalette = {
  ...palettes.dark,
  background: {
    ...palettes.dark.background,
    default: "#0e1317", // --color-bg (obsidian ink)
    paper: "#141b20", // --color-surface
  },
  status: {
    ...palettes.dark.status,
    ok: "#5b9c78", // --color-ok
    warning: "#c89a3c", // --color-warn
    error: "#b4553c", // --color-sanguine (Leonardo's red chalk)
    running: "#5980a6", // --color-accent (steel)
    pending: "#9aa3a9",
    aborted: "#5a646c",
  },
  primary: {
    ...palettes.dark.primary,
    main: "#5980a6", // --color-accent (steel)
    light: "#93b0ca", // --color-accent-text
    dark: "#3e5e7d",
    contrastText: "#0e1317",
  },
  secondary: {
    ...palettes.dark.secondary,
    main: "#b4553c", // --color-sanguine
    light: "#d2907b",
    dark: "#8b3d29",
    contrastText: "#ffffff",
  },
  text: {
    ...palettes.dark.text,
    primary: "#e7e4dd", // --color-text (paper)
    secondary: "#9aa3a9", // --color-text-dim
    disabled: "#5a646c",
    hint: "#9aa3a9",
  },
  border: "rgba(231, 228, 221, 0.12)",
  divider: "rgba(231, 228, 221, 0.12)",
  textVerySubtle: "#5a646c",
  textSubtle: "#9aa3a9",
  navigation: {
    ...palettes.dark.navigation,
    background: "#0e1317",
    indicator: "#5980a6",
    color: "#9aa3a9",
    selectedColor: "#e7e4dd",
    navItem: {
      hoverBackground: "rgba(89, 128, 166, 0.14)",
    },
    submenu: {
      background: "#141b20",
    },
  },
  pinSidebarButton: {
    icon: "#9aa3a9",
    background: "#141b20",
  },
  tabbar: {
    indicator: "#5980a6",
  },
};

const vitruvianLightPalette = {
  ...palettes.light,
  background: {
    ...palettes.light.background,
    default: "#f6f4ee", // --color-bg light
    paper: "#ffffff", // --color-surface light
  },
  status: {
    ...palettes.light.status,
    ok: "#3d7857",
    warning: "#9c6f1f",
    error: "#9c3d26",
    running: "#3e5e7d",
    pending: "#6b767e",
    aborted: "#87929a",
  },
  primary: {
    ...palettes.light.primary,
    main: "#3e5e7d",
    light: "#5980a6",
    dark: "#273e55",
    contrastText: "#ffffff",
  },
  secondary: {
    ...palettes.light.secondary,
    main: "#9c3d26",
    light: "#b4553c",
    dark: "#732a18",
    contrastText: "#ffffff",
  },
  text: {
    ...palettes.light.text,
    primary: "#1c2226",
    secondary: "#555f66",
    disabled: "#87929a",
    hint: "#555f66",
  },
  border: "rgba(28, 34, 38, 0.12)",
  divider: "rgba(28, 34, 38, 0.12)",
  textVerySubtle: "#87929a",
  textSubtle: "#555f66",
  navigation: {
    ...palettes.light.navigation,
    background: "#141b20",
    indicator: "#5980a6",
    color: "#9aa3a9",
    selectedColor: "#e7e4dd",
    navItem: {
      hoverBackground: "rgba(89, 128, 166, 0.14)",
    },
    submenu: {
      background: "#1b2429",
    },
  },
  pinSidebarButton: {
    icon: "#9aa3a9",
    background: "#141b20",
  },
  tabbar: {
    indicator: "#3e5e7d",
  },
};

const pageThemeDark = {
  home: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  app: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  apis: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  docs: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  tool: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  service: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  website: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  library: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
  other: genPageTheme({ colors: ["#0e1317", "#141b20"], shape: shapes.wave }),
};

const pageThemeLight = {
  home: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  app: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  apis: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  docs: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  tool: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  service: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  website: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  library: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
  other: genPageTheme({ colors: ["#3e5e7d", "#5980a6"], shape: shapes.wave }),
};

export const vitruvianDarkTheme = createUnifiedTheme({
  palette: vitruvianDarkPalette,
  typography: {
    fontFamily:
      '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    headings: {
      fontFamily:
        '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    },
  },
  fontFamily:
    '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  defaultPageTheme: "home",
  pageTheme: pageThemeDark,
});

export const vitruvianLightTheme = createUnifiedTheme({
  palette: vitruvianLightPalette,
  typography: {
    fontFamily:
      '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    headings: {
      fontFamily:
        '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    },
  },
  fontFamily:
    '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  defaultPageTheme: "home",
  pageTheme: pageThemeLight,
});
