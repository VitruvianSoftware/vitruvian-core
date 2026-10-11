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

/* global console */

// The watch list, kept as one JSON file in the sidecar's private data folder
// so it survives restarts and plugin updates.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";

import { cleanSettings } from "./pace.mjs";

export const watchKey = (repo, number) => `${repo.toLowerCase()}#${number}`;

export class Store {
  #file;
  #data;

  constructor(file) {
    this.#file = file;
    this.#data = { watches: {} };
    if (existsSync(file)) {
      try {
        const parsed = JSON.parse(readFileSync(file, "utf8"));
        if (parsed && typeof parsed.watches === "object") this.#data = parsed;
      } catch (err) {
        console.error(
          `gh-watch: could not read ${file}, starting empty: ${err.message}`,
        );
      }
    }
  }

  list() {
    return Object.values(this.#data.watches);
  }

  get(key) {
    return this.#data.watches[key];
  }

  put(watch) {
    this.#data.watches[watch.key] = watch;
    this.#save();
  }

  remove(key) {
    delete this.#data.watches[key];
    this.#save();
  }

  // Sightings of flaky checks; see flakes.mjs for the shape.
  flakes() {
    return this.#data.flakes ?? {};
  }

  setFlakes(table) {
    this.#data.flakes = table;
    this.#save();
  }

  // Always valid: missing or out-of-range values fall back to defaults.
  settings() {
    return cleanSettings(this.#data.settings);
  }

  // Lays `input` over the saved settings and returns what was stored.
  updateSettings(input) {
    this.#data.settings = cleanSettings(input, this.settings());
    this.#save();
    return this.#data.settings;
  }

  #save() {
    mkdirSync(dirname(this.#file), { recursive: true });
    const tmp = `${this.#file}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.#data, null, 2), "utf8");
    renameSync(tmp, this.#file);
  }
}
