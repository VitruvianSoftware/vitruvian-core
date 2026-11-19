/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export type GameState =
  "LOBBY" | "GAME_START" | "PLAYING" | "GAME_END" | "SCOREBOARD";

export interface Player {
  id: number;
  name: string;
  color: string;
  score: number;
  wins: number;
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
