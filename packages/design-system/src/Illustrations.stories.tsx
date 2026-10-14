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
import { Plate, BrandMark, BrandLogo, BrandMedallion } from "./Plate.js";
import { Label } from "./Tag.js";

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

export const OfficialBrandLogos: StoryObj = {
  render: () => (
    <div className="grid grid-cols-3 gap-5">
      <Plate field="sm" className="p-5 flex flex-col justify-between gap-4">
        <Label accent>I. Vector BrandMark (Golden-Datum V)</Label>
        <div className="flex items-center justify-center gap-5 py-4">
          <BrandMark size={72} />
          <BrandMark size={34} />
          <BrandMark size={16} />
        </div>
        <span className="text-xs text-steel-dim font-mono">
          72px · 34px · 16px responsive scale
        </span>
      </Plate>

      <Plate field="sm" className="p-5 flex flex-col justify-between gap-4">
        <Label accent>II. Official Wordmark Lockups</Label>
        <div className="flex flex-col gap-4 py-2">
          <BrandLogo markSize={34} />
          <BrandLogo title="VITRUVIAN" subtitle="TABULA SUITE" markSize={28} />
        </div>
        <span className="text-xs text-steel-dim font-mono">
          IBM Plex Sans + JetBrains Mono lockup
        </span>
      </Plate>

      <Plate field="sm" className="p-5 flex flex-col justify-between gap-4">
        <Label accent>III. Circular Gunmetal Medallion</Label>
        <div className="flex items-center justify-center gap-5 py-2">
          <BrandMedallion size={96} />
          <BrandMedallion size={48} />
        </div>
        <span className="text-xs text-steel-dim font-mono">
          src/brand/vitruvian-medallion.png (transparent alpha)
        </span>
      </Plate>
    </div>
  ),
};

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
