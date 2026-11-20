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

// DARK! — tap any tile on the 4×4 grid to toggle it and its neighbours. Turn
// every light off to score +50 and unlock a deeper scramble.

import { useEffect, useMemo, useRef, useState, type PointerEvent } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import {
  GameScreen,
  PlayerPanels,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { shuffle } from "../kit/logic";

export const sticker = (
  <>
    <rect x="10" y="10" width="100" height="100" rx="20" fill="#0F0C29" />
    <rect x="20" y="20" width="36" height="36" rx="9" fill="#FFD700" />
    <circle cx="32" cy="32" r="5" fill="#FFFFFF" stroke="none" />
    <rect x="64" y="20" width="36" height="36" rx="9" fill="#16213E" />
    <rect x="20" y="64" width="36" height="36" rx="9" fill="#16213E" />
    <rect x="64" y="64" width="36" height="36" rx="9" fill="#FFD700" />
    <circle cx="76" cy="76" r="5" fill="#FFFFFF" stroke="none" />
  </>
);

const ALL_CELLS = Array.from({ length: 16 }, (_, i) => i);

function toggleAt(grid: boolean[], idx: number): boolean[] {
  const next = [...grid];
  const r = Math.floor(idx / 4);
  const c = idx % 4;
  next[idx] = !next[idx];
  if (r > 0) next[idx - 4] = !next[idx - 4];
  if (r < 3) next[idx + 4] = !next[idx + 4];
  if (c > 0) next[idx - 1] = !next[idx - 1];
  if (c < 3) next[idx + 1] = !next[idx + 1];
  return next;
}

function makeBoards(rand: () => number, count: number): boolean[][] {
  return Array.from({ length: count }, (_, i) => {
    const taps = Math.min(10, 3 + i);
    for (let attempt = 0; attempt < 12; attempt++) {
      let grid = new Array<boolean>(16).fill(false);
      for (const cell of shuffle(rand, ALL_CELLS).slice(0, taps)) {
        grid = toggleAt(grid, cell);
      }
      if (grid.some(Boolean)) return grid;
    }
    return toggleAt(new Array<boolean>(16).fill(false), 5);
  });
}

function Board({
  player,
  round,
  boards,
}: {
  player: Player;
  round: Round;
  boards: boolean[][];
}) {
  const [boardIdx, setBoardIdx] = useState(0);
  const [grid, setGrid] = useState<boolean[]>(() => boards[0]);
  const [moves, setMoves] = useState(0);
  const [won, setWon] = useState(false);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const active = round.canPlay(player.id) && !won;

  const tap = (idx: number) => {
    if (!active) return;
    const nextGrid = toggleAt(grid, idx);
    setGrid(nextGrid);
    setMoves((m) => m + 1);
    if (nextGrid.every((on) => !on)) {
      round.addScore(player.id, 50);
      setWon(true);
      timerRef.current = window.setTimeout(() => {
        const nextIdx = boardIdx + 1;
        setBoardIdx(nextIdx);
        setGrid(boards[nextIdx % boards.length]);
        setMoves(0);
        setWon(false);
      }, 450);
    }
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-3 min-h-0">
      <div className="flex items-center justify-between w-full max-w-[220px] text-xs font-black uppercase tracking-widest shrink-0">
        <span className="text-white/50">Board {boardIdx + 1}</span>
        <span className="text-brand-cyan tabular-nums">Moves {moves}</span>
      </div>

      <div
        className="relative flex-1 min-h-0 w-full flex items-center justify-center"
        style={{ containerType: "size" }}
      >
        <div
          className="relative grid grid-cols-4 grid-rows-4 gap-1.5 sm:gap-2"
          style={{
            width: "min(100cqw, 100cqh, 220px)",
            height: "min(100cqw, 100cqh, 220px)",
          }}
        >
          {grid.map((lit, idx) => (
            <motion.button
              key={idx}
              type="button"
              whileTap={{ scale: 0.9 }}
              onPointerDown={(e: PointerEvent<HTMLButtonElement>) => {
                e.preventDefault();
                tap(idx);
              }}
              disabled={!active}
              aria-label={`Light ${idx + 1} ${lit ? "on" : "off"}`}
              className={`rounded-xl border-2 transition-colors cursor-pointer disabled:cursor-default ${
                lit
                  ? "bg-brand-gold border-white shadow-[0_0_16px_rgba(255,215,0,0.55)]"
                  : "bg-white/5 border-white/15 hover:bg-white/10"
              }`}
            />
          ))}

          {won && (
            <div className="absolute inset-0 rounded-2xl bg-brand-green/25 border-2 border-brand-green flex items-center justify-center pointer-events-none">
              <span className="text-3xl font-black italic uppercase text-brand-green drop-shadow-[0_2px_10px_rgba(0,0,0,0.9)]">
                +50!
              </span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function LightsGame(props: GameProps) {
  const round = useRound(props, { gameId: "lights", seconds: 35 });
  const boards = useMemo(() => makeBoards(round.random(), 20), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="DARK!"
      howTo="Turn every light off"
      detail="Each tap flips neighbours · +50 per board"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} boards={boards} />}
      </PlayerPanels>
    </GameScreen>
  );
}
