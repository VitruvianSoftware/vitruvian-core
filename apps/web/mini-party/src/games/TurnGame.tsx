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

// TURN! — rotate each of your arrows 90° clockwise until your row matches the
// target row. Later puzzles expand from 3 to 4 arrows.

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import {
  GameScreen,
  PlayerPanels,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { randInt } from "../kit/logic";

export const sticker = (
  <>
    <path
      d="M84 40 A 30 30 0 1 1 36 40"
      stroke="#00F2FF"
      strokeWidth="12"
      strokeLinecap="round"
      fill="none"
    />
    <polygon points="88,20 98,48 70,42" fill="#00F2FF" />
    <polygon
      points="60,26 80,50 68,50 68,78 52,78 52,50 40,50"
      fill="#FFD700"
    />
  </>
);

interface TurnPuzzle {
  target: number[];
  start: number[];
}

function makePuzzles(rand: () => number, count: number): TurnPuzzle[] {
  return Array.from({ length: count }, (_, i) => {
    const len = i < 4 ? 3 : 4;
    const target = Array.from({ length: len }, () => randInt(rand, 0, 3));
    const start = target.map((d) => (d + randInt(rand, 1, 3)) % 4);
    return { target, start };
  });
}

function ArrowGlyph({ color }: { color: string }) {
  return (
    <g fill={color}>
      <polygon points="50,14 82,48 63,48 63,84 37,84 37,48 18,48" />
    </g>
  );
}

function Board({
  player,
  round,
  puzzles,
}: {
  player: Player;
  round: Round;
  puzzles: TurnPuzzle[];
}) {
  const [puzzleIdx, setPuzzleIdx] = useState(0);
  const [angles, setAngles] = useState<number[]>(() =>
    puzzles[0].start.map((d) => d * 90),
  );
  const [solved, setSolved] = useState(false);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const cur = puzzles[puzzleIdx % puzzles.length];
  const active = round.canPlay(player.id) && !solved;

  const rotateOne = (idx: number) => {
    if (!active) return;
    const nextAngles = angles.map((deg, j) => (j === idx ? deg + 90 : deg));
    setAngles(nextAngles);

    const allMatch = cur.target.every(
      (dir, j) => (((nextAngles[j] / 90) % 4) + 4) % 4 === dir,
    );
    if (allMatch) {
      setSolved(true);
      round.addScore(player.id, 15);
      timerRef.current = window.setTimeout(() => {
        const nextIdx = puzzleIdx + 1;
        setPuzzleIdx(nextIdx);
        setAngles(puzzles[nextIdx % puzzles.length].start.map((d) => d * 90));
        setSolved(false);
      }, 260);
    }
  };

  return (
    <div className="h-full flex flex-col justify-evenly gap-2 p-3 sm:p-4 min-h-0">
      <div className="flex flex-col items-center gap-1.5">
        <span className="text-[10px] sm:text-xs font-black uppercase tracking-widest text-white/50">
          TARGET
        </span>
        <div
          className={`grid gap-2 w-full max-w-md ${
            cur.target.length === 3 ? "grid-cols-3" : "grid-cols-4"
          }`}
        >
          {cur.target.map((dir, j) => (
            <div
              key={`${puzzleIdx}-t-${j}`}
              className="aspect-square max-h-20 mx-auto w-full rounded-2xl bg-brand-bg/90 border-2 border-white/15 flex items-center justify-center p-2"
            >
              <svg
                viewBox="0 0 100 100"
                className="w-full h-full"
                style={{ transform: `rotate(${dir * 90}deg)` }}
              >
                <ArrowGlyph color="#00F2FF" />
              </svg>
            </div>
          ))}
        </div>
      </div>

      <div className="flex flex-col items-center gap-1.5">
        <span className="text-[10px] sm:text-xs font-black uppercase tracking-widest text-white/50">
          {solved ? (
            <span className="text-brand-green text-sm font-black italic">
              +15!
            </span>
          ) : (
            "YOURS (TAP TO TURN)"
          )}
        </span>
        <div
          className={`grid gap-2 w-full max-w-md ${
            cur.target.length === 3 ? "grid-cols-3" : "grid-cols-4"
          }`}
        >
          {angles.map((deg, j) => {
            const matches = (((deg / 90) % 4) + 4) % 4 === cur.target[j];
            return (
              <button
                key={`${puzzleIdx}-u-${j}`}
                type="button"
                onPointerDown={(e) => {
                  e.preventDefault();
                  rotateOne(j);
                }}
                disabled={!active}
                className={`aspect-square max-h-24 mx-auto w-full rounded-2xl border-2 flex items-center justify-center p-2 touch-none cursor-pointer transition-colors active:scale-95 disabled:cursor-default ${
                  solved
                    ? "bg-brand-green/30 border-brand-green shadow-[0_0_16px_#4ECCA366]"
                    : matches
                      ? "bg-brand-green/20 border-brand-green"
                      : "bg-white/5 border-white/15 hover:bg-white/10"
                }`}
                aria-label={`Rotate arrow ${j + 1}`}
              >
                <motion.svg
                  key={`${puzzleIdx}-${j}`}
                  viewBox="0 0 100 100"
                  className="w-full h-full"
                  initial={{ rotate: deg }}
                  animate={{ rotate: deg }}
                  transition={{ type: "spring", stiffness: 520, damping: 28 }}
                >
                  <ArrowGlyph
                    color={matches || solved ? "#4ECCA3" : "#FFD700"}
                  />
                </motion.svg>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default function TurnGame(props: GameProps) {
  const round = useRound(props, { gameId: "turn", seconds: 25 });
  const puzzles = useMemo(
    () => makePuzzles(round.random(), 50),
    [round.random],
  );

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="TURN!"
      howTo="Tap your arrows to match the target row"
      detail="Each tap turns 90° clockwise · +15 per match"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} puzzles={puzzles} />}
      </PlayerPanels>
    </GameScreen>
  );
}
