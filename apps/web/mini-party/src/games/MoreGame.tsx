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

// MORE! — two boxes scattered with 5–25 dots appear; tap the box with more
// dots. Correct picks score +10 plus up to +10 streak bonus; wrong −5.

import { useEffect, useMemo, useRef, useState } from "react";
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
    <rect x="8" y="34" width="46" height="62" rx="10" fill="#4D79FF" />
    <circle cx="23" cy="54" r="5" fill="#FFFFFF" stroke="none" />
    <circle cx="39" cy="66" r="5" fill="#FFFFFF" stroke="none" />
    <circle cx="24" cy="79" r="5" fill="#FFFFFF" stroke="none" />
    <rect x="64" y="18" width="48" height="78" rx="10" fill="#4ECCA3" />
    <circle cx="79" cy="36" r="5" fill="#FFD700" stroke="none" />
    <circle cx="97" cy="39" r="5" fill="#FFD700" stroke="none" />
    <circle cx="81" cy="56" r="5" fill="#FFD700" stroke="none" />
    <circle cx="96" cy="60" r="5" fill="#FFD700" stroke="none" />
    <circle cx="80" cy="78" r="5" fill="#FFD700" stroke="none" />
    <circle cx="97" cy="80" r="5" fill="#FFD700" stroke="none" />
  </>
);

interface Dot {
  x: number;
  y: number;
}

interface Puzzle {
  left: Dot[];
  right: Dot[];
  answer: "left" | "right";
}

function scatterDots(rand: () => number, count: number): Dot[] {
  const dots: Dot[] = [];
  for (let i = 0; i < count; i++) {
    let chosen: Dot = { x: 12 + rand() * 76, y: 12 + rand() * 76 };
    const thresholds = [13, 9, 5];
    let placed = false;
    for (const minDist of thresholds) {
      for (let tries = 0; tries < 36; tries++) {
        const cand = { x: 12 + rand() * 76, y: 12 + rand() * 76 };
        if (dots.every((d) => Math.hypot(d.x - cand.x, d.y - cand.y) >= minDist)) {
          chosen = cand;
          placed = true;
          break;
        }
      }
      if (placed) break;
    }
    dots.push(chosen);
  }
  return dots;
}

function makePuzzles(rand: () => number, count: number): Puzzle[] {
  return Array.from({ length: count }, (_, i) => {
    const low =
      i < 4 ? randInt(rand, 5, 12) : i < 10 ? randInt(rand, 9, 17) : randInt(rand, 12, 23);
    const maxDiff = Math.min(25 - low, i < 4 ? 7 : i < 10 ? 4 : 2);
    const minDiff = i < 4 ? Math.min(4, maxDiff) : i < 10 ? Math.min(2, maxDiff) : 1;
    const high = low + randInt(rand, minDiff, maxDiff);
    const leftWins = rand() < 0.5;
    return {
      left: scatterDots(rand, leftWins ? high : low),
      right: scatterDots(rand, leftWins ? low : high),
      answer: leftWins ? "left" : "right",
    };
  });
}

function Board({
  player,
  round,
  puzzles,
}: {
  player: Player;
  round: Round;
  puzzles: Puzzle[];
}) {
  const [index, setIndex] = useState(0);
  const [streak, setStreak] = useState(0);
  const [flash, setFlash] = useState<{
    picked: "left" | "right";
    ok: boolean;
    delta: number;
  } | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const puzzle = puzzles[index % puzzles.length];
  const canTap = round.canPlay(player.id) && !flash;

  const choose = (side: "left" | "right") => {
    if (!canTap) return;
    const ok = side === puzzle.answer;
    const delta = ok ? 10 + Math.min(10, streak * 2) : -5;
    round.addScore(player.id, delta);
    setStreak(ok ? streak + 1 : 0);
    setFlash({ picked: side, ok, delta });

    timerRef.current = window.setTimeout(() => {
      setFlash(null);
      setIndex((n) => n + 1);
    }, ok ? 260 : 460);
  };

  return (
    <div className="h-full flex flex-col items-center justify-center gap-2 p-2.5">
      <div className="shrink-0 h-5 flex items-center justify-center gap-2">
        {flash ? (
          <span
            className={`text-sm font-black italic uppercase ${
              flash.ok ? "text-brand-green" : "text-[#FF4D4D]"
            }`}
          >
            {flash.delta > 0 ? `+${flash.delta}` : `${flash.delta}`}
          </span>
        ) : streak > 0 ? (
          <span className="text-[11px] font-black italic uppercase tracking-wider text-brand-gold">
            STREAK ×{streak} (+{Math.min(10, streak * 2)})
          </span>
        ) : (
          <span className="text-[11px] font-black italic uppercase tracking-wider text-white/40">
            PICK MORE DOTS
          </span>
        )}
      </div>

      <div className="flex-1 min-h-0 w-full flex items-center justify-center">
        <div className="grid grid-cols-2 gap-2.5 w-full h-full max-w-[300px] max-h-[210px]">
          {(["left", "right"] as const).map((side) => {
            const dots = side === "left" ? puzzle.left : puzzle.right;
            const picked = flash?.picked === side;
            const tone = picked
              ? flash.ok
                ? "border-brand-green bg-brand-green/20 shadow-[0_0_16px_rgba(78,204,163,0.45)]"
                : "border-[#FF4D4D] bg-[#FF4D4D]/25 shadow-[0_0_16px_rgba(255,77,77,0.45)]"
              : "border-white/15 bg-brand-bg/60 hover:bg-white/10";
            return (
              <button
                key={`${index}-${side}`}
                type="button"
                disabled={!canTap}
                onPointerDown={(e) => {
                  e.preventDefault();
                  choose(side);
                }}
                className={`relative rounded-2xl border-2 p-2 cursor-pointer active:scale-95 transition-all disabled:cursor-default ${tone}`}
                aria-label={`${side} box`}
              >
                <svg viewBox="0 0 100 100" className="w-full h-full">
                  {dots.map((d, di) => (
                    <circle
                      key={di}
                      cx={d.x}
                      cy={d.y}
                      r="5.2"
                      fill="#FFD700"
                      stroke="#0F0C29"
                      strokeWidth="1.5"
                    />
                  ))}
                </svg>
                {flash && (
                  <span className="absolute bottom-1.5 right-2 text-xs font-black italic tabular-nums text-white/85">
                    {dots.length}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default function MoreGame(props: GameProps) {
  const round = useRound(props, { gameId: "more", seconds: 25 });
  const puzzles = useMemo(() => makePuzzles(round.random(), 60), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="MORE!"
      howTo="Tap the box with more dots"
      detail="+10 (+2 per streak, max +10) · −5 wrong"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} puzzles={puzzles} />}
      </PlayerPanels>
    </GameScreen>
  );
}
