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
 * Typed programmatic token surface mirroring `src/tokens.json` and `src/tokens.css`.
 * Validated in CI by `//packages/design-system:tokens_are_current` so `tokens.css`,
 * `tokens.json`, and `tokens.ts` can never drift apart.
 */
export const VitruvianTokens = {
  color: {
    dark: {
      bg: "#0e1317",
      surface: "#141b20",
      surface2: "#1b2429",
      text: "#e7e4dd",
      textDim: "#9aa3a9",
      divider: "#e7e4dd26",
      line: "#e7e4dd0f",
      accent: "#5980a6",
      accentText: "#93b0ca",
      accentQuiet: "#5980a62e",
      onAccent: "#0e1317",
      sanguine: "#b4553c",
      sanguineText: "#d2907b",
      accentDanger: "#d2907b",
      ok: "#5b9c78",
      warn: "#c89a3c",
      crit: "#b4553c",
      glassBg: "#141b20a8",
      glassBorder: "#e7e4dd26",
    },
    light: {
      bg: "#eeebe4",
      surface: "#f5f3ee",
      surface2: "#e5e1d8",
      text: "#1a2024",
      textDim: "#5c666d",
      divider: "#1a20242e",
      line: "#1a202414",
      accent: "#5980a6",
      accentText: "#3b5776",
      accentQuiet: "#5980a629",
      onAccent: "#f5f3ee",
      sanguine: "#b4553c",
      sanguineText: "#7e3a29",
      accentDanger: "#7e3a29",
      ok: "#3f7a5b",
      warn: "#94702a",
      crit: "#b4553c",
      glassBg: "#f5f3eeb3",
      glassBorder: "#1a20242e",
    },
  },
  steel: {
    100: "#eff4f9",
    200: "#d8e4ee",
    300: "#bacfe0",
    400: "#93b0ca",
    500: "#5980a6",
    600: "#4a6d90",
    700: "#3b5776",
    800: "#2c405a",
    900: "#1e2c3d",
  },
  sanguine: {
    100: "#faeeea",
    200: "#f2d8cf",
    300: "#e5b8a8",
    400: "#d2907b",
    500: "#b4553c",
    600: "#9c4832",
    700: "#7e3a29",
    800: "#5c2c20",
    900: "#3d1f17",
  },
  neutral: {
    100: "#f2f3f4",
    200: "#dee1e3",
    300: "#c2c7cb",
    400: "#9ca4aa",
    500: "#778087",
    600: "#5a6369",
    700: "#40474c",
    800: "#2a3035",
    900: "#151a1e",
  },
  font: {
    family: {
      display: [
        "JetBrains Mono",
        "ui-monospace",
        "SFMono-Regular",
        "monospace",
      ],
      body: ["IBM Plex Sans", "system-ui", "sans-serif"],
      mono: ["JetBrains Mono", "ui-monospace", "SFMono-Regular", "monospace"],
    },
    weight: {
      display: 500,
      body: 400,
      label: 500,
    },
    size: {
      h1: 40,
      h2: 29,
      h3: 22,
      h4: 17,
      h5: 14,
      h6: 11,
      body: 15,
      small: 12,
      label: 10,
      mono: 13,
      mobileH1: 29,
      mobileH2: 22,
      mobileH3: 17,
      mobileBody: 15,
    },
  },
  space: {
    1: 3,
    2: 5,
    3: 8,
    4: 13,
    5: 21,
    6: 34,
    7: 55,
    8: 89,
  },
  hit: {
    1: 44,
    2: 55,
  },
  radius: {
    sm: 0,
    md: 0,
    lg: 0,
  },
  motion: {
    duration: {
      1: 90,
      2: 140,
      3: 220,
      4: 340,
    },
    easing: {
      mech: [0.2, 0, 0.3, 1] as const,
      snap: [0.45, 0, 0.15, 1] as const,
    },
  },
} as const;

export const tokens = VitruvianTokens;
export type VitruvianColorScheme = typeof VitruvianTokens.color.dark;
