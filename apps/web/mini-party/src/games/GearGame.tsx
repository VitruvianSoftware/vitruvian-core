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

// GEARS! — trace the chain of meshed gears from the spinning clockwise drive
// gear to decide which way the final gold gear turns.

import { useEffect, useMemo, useRef, useState } from "react";
import { RotateCcw, RotateCw } from "lucide-react";
import { Player } from "../types";
import { ChoiceButton, GameScreen, PlayerPanels, useFrame, useRound, type GameProps, type Round } from "../kit/round";
import { randInt } from "../kit/logic";

function buildGearPath(teeth: number, rOut: number, rIn: number): string {
  const step = (Math.PI * 2) / teeth;
  const pts: string[] = [];
  for (let i = 0; i < teeth; i++) {
    const base = i * step;
    for (const [ang, r] of [
      [base - step * 0.28, rIn],
      [base - step * 0.14, rOut],
      [base + step * 0.14, rOut],
      [base + step * 0.28, rIn],
    ] as const) {
      pts.push(`${(Math.cos(ang) * r).toFixed(1)},${(Math.sin(ang) * r).toFixed(1)}`);
    }
  }
  return `M ${pts.join(" L ")} Z`;
}

const GEAR_PATH = buildGearPath(12, 21, 15);
const STICKER_BIG = buildGearPath(10, 34, 25);
const STICKER_SMALL = buildGearPath(8, 25, 18);

export const sticker = (
  <>
    <g transform="translate(42,66)">
      <path d={STICKER_BIG} fill="#00F2FF" />
      <circle cx="0" cy="0" r="11" fill="#0F0C29" />
    </g>
    <g transform="translate(86,42) rotate(16)">
      <path d={STICKER_SMALL} fill="#FFD700" />
      <circle cx="0" cy="0" r="8" fill="#0F0C29" />
    </g>
  </>
);

interface GearPuzzle {
  centers: { x: number; y: number }[];
  viewBox: string;
  answer: "cw" | "ccw";
}

function makePuzzles(rand: () => number, total: number): GearPuzzle[] {
  const dist = 36;
  return Array.from({ length: total }, () => {
    const count = randInt(rand, 3, 7);
    const zigzag = rand() < 0.5;
    const startSign = rand() < 0.5 ? 1 : -1;
    const centers: { x: number; y: number }[] = [{ x: 0, y: 0 }];

    for (let k = 1; k < count; k++) {
      const alphaDeg = zigzag ? ((k - 1) % 2 === 0 ? startSign * 30 : -startSign * 30) : 0;
      const rad = (alphaDeg * Math.PI) / 180;
      const prev = centers[k - 1];
      centers.push({ x: prev.x + dist * Math.cos(rad), y: prev.y + dist * Math.sin(rad) });
    }

    const xs = centers.map((c) => c.x);
    const ys = centers.map((c) => c.y);
    const minX = Math.min(...xs) - 28;
    const minY = Math.min(...ys) - 28;
    const maxX = Math.max(...xs) + 28;
    const maxY = Math.max(...ys) + 28;

    return {
      centers,
      viewBox: `${minX.toFixed(0)} ${minY.toFixed(0)} ${(maxX - minX).toFixed(0)} ${(maxY - minY).toFixed(0)}`,
      answer: (count - 1) % 2 === 0 ? "cw" : "ccw",
    };
  });
}

function SpinArrow({ cw, color }: { cw: boolean; color: string }) {
  return cw ? (
    <g stroke={color} strokeWidth="3" fill="none" strokeLinecap="round">
      <path d="M -10.4 6 A 12 12 0 1 1 12 0" />
      <polygon points="12,5 8,-1.5 16,-1.5" fill={color} stroke="none" />
    </g>
  ) : (
    <g stroke={color} strokeWidth="3" fill="none" strokeLinecap="round">
      <path d="M 10.4 6 A 12 12 0 1 0 -12 0" />
      <polygon points="-12,5 -16,-1.5 -8,-1.5" fill={color} stroke="none" />
    </g>
  );
}

function Board({ player, round, puzzles }: { player: Player; round: Round; puzzles: GearPuzzle[] }) {
  const [puzzleIdx, setPuzzleIdx] = useState(0);
  const [spin, setSpin] = useState(0);
  const [answered, setAnswered] = useState<{ pick: "cw" | "ccw"; ok: boolean } | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const active = round.canPlay(player.id);
  useFrame(active, (dt) => {
    setSpin((a) => (a + 75 * dt) % 360);
  });

  const puzzle = puzzles[puzzleIdx % puzzles.length];
  const lastIdx = puzzle.centers.length - 1;

  const choose = (pick: "cw" | "ccw") => {
    if (!active || answered) return;
    const ok = pick === puzzle.answer;
    round.addScore(player.id, ok ? 10 : -5);
    setAnswered({ pick, ok });
    timerRef.current = window.setTimeout(() => {
      setAnswered(null);
      setPuzzleIdx((i) => i + 1);
    }, 680);
  };

  return (
    <div className="h-full flex flex-col justify-between gap-2 p-2.5 sm:p-4 min-h-0">
      <div className="flex-1 min-h-0 rounded-2xl bg-brand-bg/90 border-2 border-white/10 p-2 flex items-center justify-center">
        <svg viewBox={puzzle.viewBox} className="w-full h-full">
          {puzzle.centers.map((c, i) => {
            const isFirst = i === 0;
            const isLast = i === lastIdx;
            const fill = isFirst ? "#00F2FF" : isLast ? "#FFD700" : i % 2 === 1 ? "#4D79FF" : "#4ECCA3";
            const basePhase = i % 2 === 1 ? 15 : 0;
            const rot = isFirst || answered !== null ? basePhase + (i % 2 === 0 ? spin : -spin) : basePhase;

            return (
              <g key={i} transform={`translate(${c.x.toFixed(1)},${c.y.toFixed(1)})`}>
                {isLast && (
                  <circle
                    cx="0"
                    cy="0"
                    r="24"
                    fill="none"
                    stroke={answered ? (answered.ok ? "#4ECCA3" : "#FF4D4D") : "#FFD700"}
                    strokeWidth="2.5"
                    strokeDasharray="5 4"
                  />
                )}
                <g transform={`rotate(${rot.toFixed(1)})`}>
                  <path d={GEAR_PATH} fill={fill} stroke="#0F0C29" strokeWidth="2.5" />
                  <circle cx="0" cy="0" r="5" fill="#0F0C29" />
                </g>
                {isFirst && <SpinArrow cw color="#0F0C29" />}
                {isLast && answered && <SpinArrow cw={puzzle.answer === "cw"} color="#0F0C29" />}
              </g>
            );
          })}
        </svg>
      </div>

      <div className="grid grid-cols-2 gap-2 shrink-0">
        <ChoiceButton
          onClick={() => choose("cw")}
          disabled={!active || !!answered}
          tone={answered?.pick === "cw" ? (answered.ok ? "good" : "bad") : "default"}
          className="py-2.5 sm:py-3 text-base sm:text-xl flex items-center justify-center gap-1.5 uppercase"
        >
          <RotateCw className="w-5 h-5 sm:w-6 sm:h-6 stroke-[2.8]" />
          <span>CLOCKWISE</span>
        </ChoiceButton>
        <ChoiceButton
          onClick={() => choose("ccw")}
          disabled={!active || !!answered}
          tone={answered?.pick === "ccw" ? (answered.ok ? "good" : "bad") : "default"}
          className="py-2.5 sm:py-3 text-base sm:text-xl flex items-center justify-center gap-1.5 uppercase"
        >
          <RotateCcw className="w-5 h-5 sm:w-6 sm:h-6 stroke-[2.8]" />
          <span>COUNTER</span>
        </ChoiceButton>
      </div>
    </div>
  );
}

export default function GearGame(props: GameProps) {
  const round = useRound(props, { gameId: "gear", seconds: 25 });
  const puzzles = useMemo(() => makePuzzles(round.random(), 50), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="GEARS!"
      howTo="Which way does the gold gear turn?"
      detail="Meshed gears alternate · +10 right · −5 wrong"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} puzzles={puzzles} />}
      </PlayerPanels>
    </GameScreen>
  );
}
