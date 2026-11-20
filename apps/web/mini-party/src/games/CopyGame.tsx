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

// COPY! — memorise the pattern flashed on the 4×4 grid, then tap the matching
// cells and press DONE. Patterns grow larger each level.

import { useEffect, useMemo, useRef, useState, type PointerEvent } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import {
  ChoiceButton,
  GameScreen,
  PlayerPanels,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { shuffle } from "../kit/logic";

export const sticker = (
  <>
    <rect x="10" y="10" width="100" height="100" rx="20" fill="#16213E" />
    <rect x="22" y="22" width="22" height="22" rx="5" fill="#00F2FF" />
    <rect x="49" y="22" width="22" height="22" rx="5" fill="#0F0C29" />
    <rect x="76" y="22" width="22" height="22" rx="5" fill="#00F2FF" />
    <rect x="22" y="49" width="22" height="22" rx="5" fill="#0F0C29" />
    <rect x="49" y="49" width="22" height="22" rx="5" fill="#00F2FF" />
    <rect x="76" y="49" width="22" height="22" rx="5" fill="#0F0C29" />
    <rect x="22" y="76" width="22" height="22" rx="5" fill="#0F0C29" />
    <rect x="49" y="76" width="22" height="22" rx="5" fill="#4ECCA3" />
    <rect x="76" y="76" width="22" height="22" rx="5" fill="#00F2FF" />
  </>
);

const ALL_CELLS = Array.from({ length: 16 }, (_, i) => i);

function makeLevels(rand: () => number, count: number): number[][] {
  return Array.from({ length: count }, (_, i) => {
    const lit = Math.min(12, 4 + i);
    return shuffle(rand, ALL_CELLS).slice(0, lit);
  });
}

type Stage = "wait" | "show" | "input" | "result";

function Board({ player, round, levels }: { player: Player; round: Round; levels: number[][] }) {
  const [level, setLevel] = useState(0);
  const [stage, setStage] = useState<Stage>("wait");
  const [selected, setSelected] = useState<number[]>([]);
  const [delta, setDelta] = useState<number | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  useEffect(() => {
    if (round.phase === "playing" && stage === "wait") {
      setStage("show");
    }
  }, [round.phase, stage]);

  useEffect(() => {
    if (round.phase !== "playing" || stage !== "show") return;
    timerRef.current = window.setTimeout(() => setStage("input"), 1200);
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, [stage, level, round.phase]);

  const target = levels[level % levels.length];
  const targetSet = useMemo(() => new Set(target), [target]);
  const selectedSet = useMemo(() => new Set(selected), [selected]);
  const active = round.canPlay(player.id) && stage === "input";

  const toggleCell = (idx: number) => {
    if (!active) return;
    setSelected((prev) => (prev.includes(idx) ? prev.filter((x) => x !== idx) : [...prev, idx]));
  };

  const submit = () => {
    if (!active || selected.length === 0) return;
    const right = selected.filter((i) => targetSet.has(i)).length;
    const wrong = selected.filter((i) => !targetSet.has(i)).length;
    const pts = right * 5 - wrong * 3;
    round.addScore(player.id, pts);
    setDelta(pts);
    setStage("result");
    timerRef.current = window.setTimeout(() => {
      setLevel((l) => l + 1);
      setSelected([]);
      setDelta(null);
      setStage("show");
    }, 650);
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-3 min-h-0">
      <div className="flex items-center justify-between w-full max-w-[210px] text-[10px] font-black uppercase tracking-widest shrink-0">
        <span className="text-white/50">Level {level + 1}</span>
        <span className={stage === "show" ? "text-brand-cyan" : "text-brand-gold"}>
          {stage === "show"
            ? "Memorise!"
            : stage === "result" && delta !== null
              ? `${delta >= 0 ? "+" : ""}${delta} pts`
              : `${selected.length} / ${target.length}`}
        </span>
      </div>

      <div className="relative flex-1 min-h-0 w-full flex items-center justify-center" style={{ containerType: "size" }}>
        <div
          className="grid grid-cols-4 grid-rows-4 gap-1.5"
          style={{ width: "min(100cqw, 100cqh, 200px)", height: "min(100cqw, 100cqh, 200px)" }}
        >
          {ALL_CELLS.map((idx) => {
            const isTarget = targetSet.has(idx);
            const isPicked = selectedSet.has(idx);
            let cellClass = "bg-white/5 border-white/15";
            if (stage === "show" && isTarget) {
              cellClass = "bg-brand-cyan border-white shadow-[0_0_14px_rgba(0,242,255,0.65)]";
            } else if (stage === "input" && isPicked) {
              cellClass = "bg-brand-gold border-white shadow-[0_0_12px_rgba(255,215,0,0.5)]";
            } else if (stage === "result") {
              if (isPicked && isTarget) cellClass = "bg-brand-green border-white";
              else if (isPicked && !isTarget) cellClass = "bg-brand-accent border-white";
              else if (!isPicked && isTarget) cellClass = "bg-brand-cyan/25 border-brand-cyan border-dashed";
            }

            return (
              <motion.button
                key={idx}
                type="button"
                whileTap={active ? { scale: 0.9 } : undefined}
                onPointerDown={(e: PointerEvent<HTMLButtonElement>) => {
                  e.preventDefault();
                  toggleCell(idx);
                }}
                disabled={!active}
                aria-label={`Cell ${idx + 1}`}
                className={`rounded-xl border-2 transition-colors cursor-pointer disabled:cursor-default ${cellClass}`}
              />
            );
          })}
        </div>
      </div>

      <ChoiceButton
        onClick={submit}
        disabled={!active || selected.length === 0}
        tone={stage === "result" && delta !== null ? (delta > 0 ? "good" : "bad") : "default"}
        className="w-full max-w-[200px] py-2 text-lg sm:text-xl shrink-0"
      >
        DONE
      </ChoiceButton>
    </div>
  );
}

export default function CopyGame(props: GameProps) {
  const round = useRound(props, { gameId: "copy", seconds: 30 });
  const levels = useMemo(() => makeLevels(round.random(), 25), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="COPY!"
      howTo="Memorise the grid, then recreate it"
      detail="+5 right cell · −3 wrong cell"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} levels={levels} />}
      </PlayerPanels>
    </GameScreen>
  );
}
