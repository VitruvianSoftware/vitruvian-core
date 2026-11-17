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

/** A weather observation, as the weather service reports it. */
export interface WeatherObservation {
  /** WMO weather code. */
  weatherCode?: number | string | null;
  cloudCoverPct?: number;
  precipitationMm?: number;
  windKph?: number;
  windDirectionDeg?: number;
  visibilityM?: number;
}

/** Bounded visual strengths, 0..1, for an observation. */
export interface WeatherEffectProfile {
  /** False where there is no observation: everything clear. */
  available: boolean;
  cloud: number;
  rain: number;
  snow: number;
  fog: number;
  haze: number;
  droplets: number;
  storm: number;
  wind: number;
  windDirectionDeg: number;
}

/**
 * The visual strengths of `weather`: the WMO code picks the kind, the
 * numbers how strong. Missing weather is clear.
 */
export function deriveWeatherEffectProfile(
  weather: WeatherObservation | null | undefined,
): WeatherEffectProfile;

/** How much of each ground weather shows from a camera `altitudeM` up, 0..1. */
export function weatherAltitudeFactors(altitudeM: number): {
  precipitation: number;
  cloud: number;
  haze: number;
};
