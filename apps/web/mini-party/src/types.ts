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

export type GameState =
  "LOBBY" | "GAME_START" | "PLAYING" | "GAME_END" | "SCOREBOARD";

export interface Player {
  id: number;
  name: string;
  color: string;
  score: number;
  wins: number;
  // Online only: false while this player's connection is down and the rooms
  // server is holding their seat for them to come back.
  connected?: boolean;
}

export interface GameResult {
  playerId: number;
  score: number;
  rank: number;
}

export const PLAYER_COLORS = [
  "#FF4D4D", // Red
  "#4D79FF", // Blue
  "#FFD93D", // Yellow
  "#6BCB77", // Green
];

export const PLAYER_NAMES = ["Player 1", "Player 2", "Player 3", "Player 4"];
