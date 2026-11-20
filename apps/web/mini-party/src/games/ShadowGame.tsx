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

// SHADOW! — match the coloured block shape to its rotated dark silhouette out
// of four choices, avoiding similar and mirror-image shapes.

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import { ChoiceButton, GameScreen, PlayerPanels, useRound, type GameProps, type Round } from "../kit/round";
import { pick, randInt, shuffle } from "../kit/logic";

export const sticker = (
  <>
    <g fill="#0F0C29" stroke="#00F2FF" strokeWidth="4">
      <rect x="64" y="64" width="22" height="22" rx="4" />
      <rect x="86" y="64" width="22" height="22" rx="4" />
      <rect x="42" y="64" width="22" height="22" rx="4" />
      <rect x="42" y="86" width="22" height="22" rx="4" />
    </g>
    <g fill="#FF0080">
      <rect x="14" y="14" width="24" height="24" rx="5" />
      <rect x="14" y="38" width="24" height="24" rx="5" />
      <rect x="14" y="62" width="24" height="24" rx="5" />
      <rect x="38" y="62" width="24" height="24" rx="5" />
    </g>
  </>
);

type Cell = readonly [number, number];
const COLORS = ["#FF0080", "#00F2FF", "#4ECCA3", "#FFD700", "#4D79FF", "#FF4D4D"];

const POLY_4: readonly (readonly Cell[])[] = [
  [[0, 0], [1, 0], [2, 0], [3, 0]],
  [[0, 0], [1, 0], [0, 1], [1, 1]],
  [[0, 0], [1, 0], [2, 0], [1, 1]],
  [[0, 0], [0, 1], [0, 2], [1, 2]],
  [[1, 0], [1, 1], [1, 2], [0, 2]],
  [[1, 0], [2, 0], [0, 1], [1, 1]],
  [[0, 0], [1, 0], [1, 1], [2, 1]],
];

const POLY_3_TARGETS: readonly (readonly Cell[])[] = [
  [[0, 0], [1, 0], [2, 0]],
  [[0, 0], [0, 1], [1, 1]],
];

const POLY_3_EXTRA: readonly (readonly Cell[])[] = [
  [[0, 0], [1, 0], [2, 1]],
  [[0, 1], [1, 0], [2, 0]],
  [[0, 0], [1, 1], [2, 0]],
];

function normalize(cells: readonly Cell[]): Cell[] {
  const minX = Math.min(...cells.map((c) => c[0]));
  const minY = Math.min(...cells.map((c) => c[1]));
  return cells.map(([x, y]): Cell => [x - minX, y - minY]).sort((a, b) => a[1] - b[1] || a[0] - b[0]);
}

function rotateN(cells: readonly Cell[], turns: number): Cell[] {
  let out = normalize(cells);
  for (let i = 0; i < turns % 4; i++) out = normalize(out.map(([x, y]): Cell => [-y, x]));
  return out;
}

function canonicalKey(cells: readonly Cell[]): string {
  let best = normalize(cells).map(([x, y]) => `${x},${y}`).join(";");
  for (let t = 1; t < 4; t++) {
    const k = rotateN(cells, t).map(([x, y]) => `${x},${y}`).join(";");
    if (k < best) best = k;
  }
  return best;
}

interface ShadowPuzzle {
  target: Cell[];
  color: string;
  options: Cell[][];
  correctIndex: number;
}

function makePuzzles(rand: () => number, count: number): ShadowPuzzle[] {
  return Array.from({ length: count }, () => {
    const useThree = rand() < 0.25;
    const target = normalize(useThree ? pick(rand, POLY_3_TARGETS) : pick(rand, POLY_4));
    const usedKeys = new Set<string>([canonicalKey(target)]);
    const distractors: Cell[][] = [];

    if (!useThree) {
      const mirrored = normalize(target.map(([x, y]): Cell => [-x, y]));
      const mKey = canonicalKey(mirrored);
      if (!usedKeys.has(mKey)) {
        usedKeys.add(mKey);
        distractors.push(rotateN(mirrored, randInt(rand, 0, 3)));
      }
    }

    const pool = useThree ? shuffle(rand, [...POLY_3_TARGETS, ...POLY_3_EXTRA]) : shuffle(rand, POLY_4);
    for (const candidate of pool) {
      if (distractors.length >= 3) break;
      const cKey = canonicalKey(candidate);
      if (usedKeys.has(cKey)) continue;
      usedKeys.add(cKey);
      distractors.push(rotateN(candidate, randInt(rand, 0, 3)));
    }

    const tagged = shuffle(rand, [
      { cells: rotateN(target, randInt(rand, 0, 3)), isMatch: true },
      ...distractors.map((cells) => ({ cells, isMatch: false })),
    ]);

    return {
      target,
      color: pick(rand, COLORS),
      options: tagged.map((o) => o.cells),
      correctIndex: tagged.findIndex((o) => o.isMatch),
    };
  });
}

function ShapeSvg({ cells, fill, stroke, className = "" }: { cells: readonly Cell[]; fill: string; stroke: string; className?: string }) {
  const w = Math.max(...cells.map((c) => c[0])) + 1;
  const h = Math.max(...cells.map((c) => c[1])) + 1;
  const size = 20;
  const ox = (100 - w * size) / 2;
  const oy = (100 - h * size) / 2;

  return (
    <svg viewBox="0 0 100 100" className={className}>
      {cells.map(([x, y], i) => (
        <rect key={i} x={ox + x * size + 1} y={oy + y * size + 1} width={size - 2} height={size - 2} rx="4" fill={fill} stroke={stroke} strokeWidth="2.5" />
      ))}
    </svg>
  );
}

function Board({ player, round, puzzles }: { player: Player; round: Round; puzzles: ShadowPuzzle[] }) {
  const [index, setIndex] = useState(0);
  const [flash, setFlash] = useState<{ idx: number; ok: boolean } | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const puzzle = puzzles[index % puzzles.length];
  const active = round.canPlay(player.id) && !flash;

  const choose = (idx: number) => {
    if (!active) return;
    const ok = idx === puzzle.correctIndex;
    round.addScore(player.id, ok ? 10 : -5);
    setFlash({ idx, ok });
    timerRef.current = window.setTimeout(() => {
      setFlash(null);
      setIndex((i) => i + 1);
    }, ok ? 200 : 420);
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-2.5 sm:p-4 min-h-0">
      <motion.div
        key={index}
        initial={{ scale: 0.9, opacity: 0.7 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.14 }}
        className="w-24 h-24 sm:w-28 sm:h-28 rounded-2xl bg-brand-bg/90 border-2 border-white/15 p-2 flex items-center justify-center shrink-0"
      >
        <ShapeSvg cells={puzzle.target} fill={puzzle.color} stroke="#0F0C29" className="w-full h-full" />
      </motion.div>

      <div className="grid grid-cols-2 grid-rows-2 gap-2 w-full flex-1 min-h-0 max-w-sm">
        {puzzle.options.map((cells, idx) => (
          <ChoiceButton
            key={`${index}-${idx}`}
            onClick={() => choose(idx)}
            disabled={!active}
            tone={flash?.idx === idx ? (flash.ok ? "good" : "bad") : "default"}
            className="p-2 min-h-0 flex items-center justify-center bg-white/15"
          >
            <ShapeSvg cells={cells} fill="#0B0820" stroke="#FFFFFF66" className="w-full h-full" />
          </ChoiceButton>
        ))}
      </div>
    </div>
  );
}

export default function ShadowGame(props: GameProps) {
  const round = useRound(props, { gameId: "shadow", seconds: 25 });
  const puzzles = useMemo(() => makePuzzles(round.random(), 60), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="SHADOW!"
      howTo="Tap the matching rotated shadow"
      detail="+10 right · −5 wrong · watch out for mirror shapes!"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} puzzles={puzzles} />}
      </PlayerPanels>
    </GameScreen>
  );
}
