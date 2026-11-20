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

// MAZE! — navigate a seeded maze with the touch d-pad. Reach the exit for
// +100 plus a time bonus, then advance to a larger maze.

import { useEffect, useMemo, useRef, useState } from "react";
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp } from "lucide-react";
import { motion } from "motion/react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useRound, type GameProps, type Round } from "../kit/round";
import { pick } from "../kit/logic";

export const sticker = (
  <>
    <rect x="12" y="12" width="96" height="96" rx="16" fill="#0F0C29" />
    <path
      d="M12 12 H108 V108 H12 Z M44 12 V76 M76 44 V108 M12 44 H44 M76 44 H108 M44 76 H76"
      stroke="#00F2FF"
      strokeWidth="9"
      strokeLinecap="round"
      strokeLinejoin="round"
      fill="none"
    />
    <circle cx="28" cy="28" r="10" fill="#FF0080" />
    <circle cx="92" cy="92" r="11" fill="#FFD700" />
  </>
);

const N = 1;
const E = 2;
const S = 4;
const W = 8;

const DIRS = [
  { dr: -1, dc: 0, bit: N, opp: S },
  { dr: 0, dc: 1, bit: E, opp: W },
  { dr: 1, dc: 0, bit: S, opp: N },
  { dr: 0, dc: -1, bit: W, opp: E },
] as const;

const DPAD = [
  { key: "up", col: "col-start-2 row-start-1", bit: N, dr: -1, dc: 0, Icon: ArrowUp, label: "Move up" },
  { key: "left", col: "col-start-1 row-start-2", bit: W, dr: 0, dc: -1, Icon: ArrowLeft, label: "Move left" },
  { key: "down", col: "col-start-2 row-start-2", bit: S, dr: 1, dc: 0, Icon: ArrowDown, label: "Move down" },
  { key: "right", col: "col-start-3 row-start-2", bit: E, dr: 0, dc: 1, Icon: ArrowRight, label: "Move right" },
] as const;

interface Maze {
  size: number;
  cells: number[];
  path: string;
}

const CELL = 16;
const PAD = 4;

function makeMaze(rand: () => number, size: number): Maze {
  const cells = new Array<number>(size * size).fill(0);
  const visited = new Array<boolean>(size * size).fill(false);
  const stack: [number, number][] = [[0, 0]];
  visited[0] = true;

  while (stack.length > 0) {
    const [r, c] = stack[stack.length - 1];
    const open = DIRS.filter(({ dr, dc }) => {
      const nr = r + dr;
      const nc = c + dc;
      return nr >= 0 && nr < size && nc >= 0 && nc < size && !visited[nr * size + nc];
    });
    if (open.length === 0) {
      stack.pop();
      continue;
    }
    const dir = pick(rand, open);
    const nr = r + dir.dr;
    const nc = c + dir.dc;
    cells[r * size + c] |= dir.bit;
    cells[nr * size + nc] |= dir.opp;
    visited[nr * size + nc] = true;
    stack.push([nr, nc]);
  }

  const end = PAD + size * CELL;
  const parts = [`M${PAD} ${PAD}H${end}`, `M${PAD} ${PAD}V${end}`];
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      const mask = cells[r * size + c];
      const x = PAD + c * CELL;
      const y = PAD + r * CELL;
      if ((mask & E) === 0) parts.push(`M${x + CELL} ${y}V${y + CELL}`);
      if ((mask & S) === 0) parts.push(`M${x} ${y + CELL}H${x + CELL}`);
    }
  }
  return { size, cells, path: parts.join(" ") };
}

function Board({ player, round, mazes }: { player: Player; round: Round; mazes: Maze[] }) {
  const [mazeIdx, setMazeIdx] = useState(0);
  const [pos, setPos] = useState({ r: 0, c: 0 });
  const [bump, setBump] = useState(false);
  const [cleared, setCleared] = useState<number | null>(null);
  const bumpTimer = useRef<number | null>(null);
  const clearTimer = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (bumpTimer.current !== null) window.clearTimeout(bumpTimer.current);
      if (clearTimer.current !== null) window.clearTimeout(clearTimer.current);
    };
  }, []);

  const maze = mazes[mazeIdx % mazes.length];
  const size = maze.size;
  const active = round.canPlay(player.id) && cleared === null;
  const viewSize = size * CELL + PAD * 2;

  const move = (bit: number, dr: number, dc: number) => {
    if (!active) return;
    if ((maze.cells[pos.r * size + pos.c] & bit) === 0) {
      setBump(true);
      if (bumpTimer.current !== null) window.clearTimeout(bumpTimer.current);
      bumpTimer.current = window.setTimeout(() => setBump(false), 180);
      return;
    }
    const nr = pos.r + dr;
    const nc = pos.c + dc;
    setPos({ r: nr, c: nc });
    if (nr === size - 1 && nc === size - 1) {
      const pts = 100 + Math.round((round.timeLeft / 35) * 100);
      round.addScore(player.id, pts);
      setCleared(pts);
      clearTimer.current = window.setTimeout(() => {
        setCleared(null);
        setMazeIdx((i) => i + 1);
        setPos({ r: 0, c: 0 });
      }, 450);
    }
  };

  const exitX = PAD + (size - 1) * CELL;
  const exitY = PAD + (size - 1) * CELL;
  const px = PAD + pos.c * CELL + CELL / 2;
  const py = PAD + pos.r * CELL + CELL / 2;

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-2 min-h-0">
      <div className="flex items-center justify-between w-full max-w-[230px] text-[10px] font-black uppercase tracking-widest text-white/50 shrink-0">
        <span>Maze {mazeIdx + 1}</span>
        <span>{size}×{size}</span>
      </div>

      <motion.div
        animate={bump ? { x: [0, -5, 5, -3, 0] } : { x: 0 }}
        transition={{ duration: 0.16 }}
        className="relative flex-1 min-h-0 w-full flex items-center justify-center"
      >
        <svg viewBox={`0 0 ${viewSize} ${viewSize}`} className="w-full h-full max-h-full">
          <rect x={PAD} y={PAD} width={size * CELL} height={size * CELL} rx={3} fill="#0F0C29" fillOpacity={0.7} />
          <rect x={exitX + 2.5} y={exitY + 2.5} width={CELL - 5} height={CELL - 5} rx={3} fill="#FFD700" />
          <circle cx={PAD + CELL / 2} cy={PAD + CELL / 2} r={CELL * 0.22} fill="none" stroke="#00F2FF" strokeOpacity={0.4} strokeWidth={1.5} />
          <path d={maze.path} stroke={bump ? "#FF0080" : "#00F2FF"} strokeWidth={2} strokeLinecap="round" fill="none" />
          <motion.circle
            cx={0}
            cy={0}
            r={CELL * 0.31}
            fill={player.color}
            stroke="#FFFFFF"
            strokeWidth={1.6}
            animate={{ x: px, y: py }}
            transition={{ type: "spring", stiffness: 520, damping: 32 }}
          />
        </svg>

        {cleared !== null && (
          <div className="absolute inset-0 flex items-center justify-center bg-brand-green/25 rounded-2xl pointer-events-none">
            <span className="text-3xl font-black italic uppercase text-brand-green drop-shadow-[0_2px_10px_rgba(0,0,0,0.9)]">
              +{cleared}!
            </span>
          </div>
        )}
      </motion.div>

      <div className="grid grid-cols-3 grid-rows-2 gap-1.5 w-full max-w-[196px] shrink-0">
        {DPAD.map(({ key, col, bit, dr, dc, Icon, label }) => (
          <button
            key={key}
            type="button"
            onPointerDown={(e) => {
              e.preventDefault();
              move(bit, dr, dc);
            }}
            disabled={!active}
            aria-label={label}
            className={`${col} h-10 sm:h-11 rounded-xl border-2 border-white/15 bg-white/10 hover:bg-white/15 active:scale-95 active:bg-brand-cyan/30 flex items-center justify-center cursor-pointer disabled:opacity-50`}
          >
            <Icon className="w-5 h-5" />
          </button>
        ))}
      </div>
    </div>
  );
}

export default function MazeGame(props: GameProps) {
  const round = useRound(props, { gameId: "maze", seconds: 35 });
  const mazes = useMemo(() => {
    const rand = round.random();
    return [7, 9, 9, 9, 9, 9].map((size) => makeMaze(rand, size));
  }, [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="MAZE!"
      howTo="Navigate to the exit"
      detail="+100 per maze + time bonus · 7×7 then 9×9"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} mazes={mazes} />}
      </PlayerPanels>
    </GameScreen>
  );
}
