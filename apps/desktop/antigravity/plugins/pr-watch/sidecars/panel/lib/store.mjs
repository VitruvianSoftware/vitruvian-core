// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

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
          `pr-watch: could not read ${file}, starting empty: ${err.message}`,
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

  #save() {
    mkdirSync(dirname(this.#file), { recursive: true });
    const tmp = `${this.#file}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.#data, null, 2), "utf8");
    renameSync(tmp, this.#file);
  }
}
