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
import type { Meta, StoryObj } from "@storybook/react-vite";
import {
  PlateFigure,
  DuotoneImage,
  VitruvianStockImages,
  type VitruvianPlateVariant,
} from "./Illustrations.js";
import { AutoGrid } from "./Layout.js";

const illustrationsMeta: Meta = {
  title: "Foundations/Technical plates & imagery",
  parameters: { layout: "padded" },
};
export default illustrationsMeta;

const PLATE_SPECS: ReadonlyArray<{
  variant: VitruvianPlateVariant;
  label: string;
  scale: string;
}> = [
  {
    variant: "proportion",
    label: "FIG. 01 // VITRUVIAN RATIO",
    scale: "1:1.618",
  },
  { variant: "spaces", label: "FIG. 02 // WORKSPACE BAYS", scale: "PLAN" },
  { variant: "tabs", label: "FIG. 03 // ORTHOGRAPHIC STACK", scale: "ISO" },
  { variant: "resources", label: "FIG. 04 // CATALOG LEDGER", scale: "INDEX" },
  { variant: "topology", label: "FIG. 05 // CLUSTER TRIAD", scale: "MESH" },
  { variant: "telemetry", label: "FIG. 06 // POLAR RETICLE", scale: "AZ/EL" },
  {
    variant: "security",
    label: "FIG. 07 // CRYPTOGRAPHIC SEAL",
    scale: "SHA256",
  },
  {
    variant: "harmonic",
    label: "FIG. 08 // ACOUSTIC HARMONIC",
    scale: "440HZ",
  },
];

export const VectorPlates: StoryObj = {
  render: () => (
    <AutoGrid minWidth={240}>
      {PLATE_SPECS.map((spec) => (
        <PlateFigure
          key={spec.variant}
          variant={spec.variant}
          figureLabel={spec.label}
          meta={spec.scale}
        />
      ))}
    </AutoGrid>
  ),
};

export const DuotoneScreenPrints: StoryObj = {
  render: () => (
    <div className="grid grid-cols-3 gap-5">
      <DuotoneImage
        src={VitruvianStockImages.TOPOGRAPHY}
        alt="Topographic contour plate"
        caption="PLATE I · TOPOGRAPHIC CONTOUR SURVEY"
      />
      <DuotoneImage
        src={VitruvianStockImages.ARMILLARY}
        alt="Armillary sphere study"
        caption="PLATE II · CELESTIAL ARMILLARY SPHERE"
      />
      <DuotoneImage
        src={VitruvianStockImages.PERSPECTIVE}
        alt="Perspective colonnade study"
        caption="PLATE III · ORTHOGRAPHIC PERSPECTIVE STUDY"
      />
    </div>
  ),
};
