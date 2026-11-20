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

// PUFF! — pump each balloon for points, then bank before it bursts. Five
// balloons per player; a popped balloon scores zero.

import { useEffect, useMemo, useRef, useState } from "react";
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
import { randInt } from "../kit/logic";

export const sticker = (
  <>
    <ellipse cx="60" cy="54" rx="34" ry="40" fill="#00F2FF" />
    <path d="M52 100 L60 90 L68 100 Z" fill="#FF0080" />
    <ellipse cx="47" cy="39" rx="7" ry="12" fill="#FFFFFF" stroke="none" transform="rotate(-24 47 39)" />
    <path
      d="M22 20 l-10 -8 M98 20 l10 -8 M60 10 v-8"
      stroke="#FFD700"
      strokeWidth="6"
      strokeLinecap="round"
      fill="none"
    />
  </>
);

interface Balloon {
  popAt: number;
  color: string;
}

const TOTAL_BALLOONS = 5;
const COLORS = ["#00F2FF", "#FF0080", "#FFD700", "#4ECCA3", "#4D79FF"];

function makeBalloons(rand: () => number): Balloon[] {
  return Array.from({ length: TOTAL_BALLOONS }, (_, i) => ({
    popAt: randInt(rand, 5, 25),
    color: COLORS[i % COLORS.length],
  }));
}

type Outcome = "idle" | "banked" | "popped";

function Board({ player, round, balloons }: { player: Player; round: Round; balloons: Balloon[] }) {
  const [idx, setIdx] = useState(0);
  const [air, setAir] = useState(0);
  const [outcome, setOutcome] = useState<Outcome>("idle");
  const [history, setHistory] = useState<("banked" | "popped")[]>([]);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const balloon = balloons[idx];
  const active = round.canPlay(player.id) && outcome === "idle";

  const advance = (delayMs: number) => {
    timerRef.current = window.setTimeout(() => {
      if (idx + 1 >= TOTAL_BALLOONS) {
        round.finish(player.id);
        return;
      }
      setIdx((i) => i + 1);
      setAir(0);
      setOutcome("idle");
    }, delayMs);
  };

  const pump = () => {
    if (!active) return;
    const nextAir = air + 1;
    setAir(nextAir);
    if (nextAir >= balloon.popAt) {
      setOutcome("popped");
      setHistory((h) => [...h, "popped"]);
      advance(620);
    }
  };

  const bank = () => {
    if (!active || air <= 0) return;
    round.addScore(player.id, air);
    setOutcome("banked");
    setHistory((h) => [...h, "banked"]);
    advance(480);
  };

  const scale = 0.44 + Math.min(air, 25) * 0.032;

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-3 min-h-0">
      <div className="flex items-center justify-between w-full max-w-[230px] shrink-0">
        <div className="flex gap-1.5">
          {balloons.map((_, i) => (
            <span
              key={i}
              className={`w-3 h-3 rounded-full ${
                history[i] === "banked"
                  ? "bg-brand-green"
                  : history[i] === "popped"
                    ? "bg-brand-accent"
                    : i === idx
                      ? "bg-white animate-pulse"
                      : "bg-white/15"
              }`}
            />
          ))}
        </div>
        <span className="text-[10px] font-black uppercase tracking-widest text-white/50">
          {idx + 1} / {TOTAL_BALLOONS}
        </span>
      </div>

      <div className="relative flex-1 min-h-0 w-full flex items-center justify-center">
        <svg viewBox="0 0 120 120" className="w-full h-full max-h-[170px]">
          {outcome === "popped" ? (
            <motion.g
              initial={{ scale: 0.7, opacity: 1 }}
              animate={{ scale: 1.25, opacity: 0.9 }}
              style={{ originX: "60px", originY: "58px" }}
            >
              <polygon
                points="60,12 72,38 102,28 84,54 108,74 78,76 82,106 58,86 34,104 42,74 12,70 38,52 20,26 48,38"
                fill="#FF0080"
                stroke="#FFD700"
                strokeWidth="3"
              />
            </motion.g>
          ) : (
            <motion.g
              animate={{ scale }}
              transition={{ type: "spring", stiffness: 420, damping: 22 }}
              style={{ originX: "60px", originY: "96px" }}
            >
              <path d="M54 98 L60 88 L66 98 Z" fill={balloon.color} stroke="#0F0C29" strokeWidth="2.5" />
              <ellipse
                cx="60"
                cy="52"
                rx="34"
                ry="40"
                fill={balloon.color}
                stroke="#FFFFFF"
                strokeWidth="3.5"
              />
              <ellipse
                cx="47"
                cy="36"
                rx="6"
                ry="11"
                fill="#FFFFFF"
                opacity="0.65"
                transform="rotate(-24 47 36)"
              />
            </motion.g>
          )}
        </svg>

        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          {outcome === "popped" ? (
            <span className="text-3xl font-black italic uppercase text-brand-gold drop-shadow-[0_2px_8px_rgba(0,0,0,0.9)]">
              POP!
            </span>
          ) : outcome === "banked" ? (
            <span className="text-3xl font-black italic uppercase text-brand-green drop-shadow-[0_2px_8px_rgba(0,0,0,0.9)]">
              +{air}!
            </span>
          ) : (
            <span className="text-3xl font-black italic tabular-nums text-white drop-shadow-[0_2px_6px_rgba(0,0,0,0.8)]">
              {air}
            </span>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 w-full max-w-[240px] shrink-0">
        <ChoiceButton
          onClick={pump}
          disabled={!active}
          className="py-3 text-lg sm:text-xl bg-brand-cyan/20 border-brand-cyan hover:bg-brand-cyan/30"
        >
          PUMP
        </ChoiceButton>
        <ChoiceButton
          onClick={bank}
          disabled={!active || air <= 0}
          tone={outcome === "banked" ? "good" : "default"}
          className="py-3 text-lg sm:text-xl"
        >
          BANK +{air}
        </ChoiceButton>
      </div>
    </div>
  );
}

export default function BalloonGame(props: GameProps) {
  const round = useRound(props, { gameId: "balloon", seconds: 30 });
  const balloons = useMemo(() => makeBalloons(round.random()), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="PUFF!"
      howTo="Pump for points — bank before it pops!"
      detail="5 balloons · popped = 0 pts"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} balloons={balloons} />}
      </PlayerPanels>
    </GameScreen>
  );
}
