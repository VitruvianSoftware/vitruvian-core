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

// HI-LO! — guess whether the next seeded card (1–13) is higher or lower. Build
// streaks for bigger multipliers; ties count as right for either choice.

import { useEffect, useMemo, useRef, useState } from "react";
import { ArrowDown, ArrowUp } from "lucide-react";
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
    <rect x="28" y="14" width="64" height="92" rx="12" fill="#FFFFFF" />
    <polygon points="60,40 76,60 60,80 44,60" fill="#FFD700" />
    <path d="M22 44 l-10 14 h20 z" fill="#4ECCA3" />
    <path d="M98 76 l-10 -14 h20 z" fill="#FF0080" />
  </>
);

interface Card {
  value: number;
  suit: number;
}

const SUIT_COLORS = ["#FF0080", "#00F2FF", "#FFD700", "#4ECCA3"];

function SuitIcon({ suit, size = 16 }: { suit: number; size?: number }) {
  const color = SUIT_COLORS[suit % SUIT_COLORS.length];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      {suit === 0 && <polygon points="12,2 22,12 12,22 2,12" fill={color} />}
      {suit === 1 && <circle cx="12" cy="12" r="9" fill={color} />}
      {suit === 2 && <polygon points="12,3 22,20 2,20" fill={color} />}
      {suit === 3 && (
        <rect x="4" y="4" width="16" height="16" rx="4" fill={color} />
      )}
    </svg>
  );
}

function makeDeck(rand: () => number, count: number): Card[] {
  return Array.from({ length: count }, () => ({
    value: randInt(rand, 1, 13),
    suit: randInt(rand, 0, 3),
  }));
}

function Board({
  player,
  round,
  deck,
}: {
  player: Player;
  round: Round;
  deck: Card[];
}) {
  const [index, setIndex] = useState(0);
  const [streak, setStreak] = useState(0);
  const [flash, setFlash] = useState<{
    ok: boolean;
    label: string;
    guess: "hi" | "lo";
  } | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const card = deck[index % deck.length];
  const active = round.canPlay(player.id) && !flash;

  const guess = (dir: "hi" | "lo") => {
    if (!active) return;
    const next = deck[(index + 1) % deck.length];
    const ok =
      dir === "hi" ? next.value >= card.value : next.value <= card.value;
    if (ok) {
      const nextStreak = streak + 1;
      const pts = 5 * nextStreak;
      round.addScore(player.id, pts);
      setStreak(nextStreak);
      setFlash({ ok: true, label: `+${pts}`, guess: dir });
    } else {
      setStreak(0);
      setFlash({ ok: false, label: "RESET", guess: dir });
    }
    setIndex((i) => i + 1);
    timerRef.current = window.setTimeout(() => setFlash(null), ok ? 180 : 320);
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-3 min-h-0">
      <div className="flex items-center justify-between w-full max-w-[230px] text-[10px] font-black uppercase tracking-widest shrink-0">
        <span className="text-brand-gold">Streak ×{streak}</span>
        <span className="text-white/50">Next +{(streak + 1) * 5}</span>
      </div>

      <div className="relative flex-1 min-h-0 w-full flex items-center justify-center">
        <motion.div
          key={index}
          initial={{ scale: 0.88, y: -8, opacity: 0.6 }}
          animate={{ scale: 1, y: 0, opacity: 1 }}
          transition={{ duration: 0.14 }}
          className={`relative w-24 h-32 sm:w-28 sm:h-36 rounded-2xl border-4 bg-white text-brand-bg flex flex-col items-center justify-center shadow-[0_10px_28px_rgba(0,0,0,0.45)] ${
            flash
              ? flash.ok
                ? "border-brand-green shadow-[0_0_24px_rgba(78,204,163,0.7)]"
                : "border-brand-accent shadow-[0_0_24px_rgba(255,0,128,0.7)]"
              : "border-white"
          }`}
        >
          <div className="absolute top-2 left-2">
            <SuitIcon suit={card.suit} size={14} />
          </div>
          <span className="text-5xl sm:text-6xl font-black italic tabular-nums leading-none">
            {card.value}
          </span>
          <div className="absolute bottom-2 right-2">
            <SuitIcon suit={card.suit} size={14} />
          </div>
        </motion.div>

        {flash && (
          <div
            className={`absolute -top-1 px-3 py-0.5 rounded-full text-xs font-black italic uppercase shadow-lg ${
              flash.ok
                ? "bg-brand-green text-brand-bg"
                : "bg-brand-accent text-white"
            }`}
          >
            {flash.label}
          </div>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2 w-full max-w-[240px] shrink-0">
        <ChoiceButton
          onClick={() => guess("lo")}
          disabled={!active}
          tone={flash?.guess === "lo" ? (flash.ok ? "good" : "bad") : "default"}
          className="py-3 text-base sm:text-lg flex items-center justify-center gap-1"
        >
          <ArrowDown className="w-5 h-5" />
          LOWER
        </ChoiceButton>
        <ChoiceButton
          onClick={() => guess("hi")}
          disabled={!active}
          tone={flash?.guess === "hi" ? (flash.ok ? "good" : "bad") : "default"}
          className="py-3 text-base sm:text-lg flex items-center justify-center gap-1"
        >
          <ArrowUp className="w-5 h-5" />
          HIGHER
        </ChoiceButton>
      </div>
    </div>
  );
}

export default function HiLoGame(props: GameProps) {
  const round = useRound(props, { gameId: "hilo", seconds: 25 });
  const deck = useMemo(() => makeDeck(round.random(), 120), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="HI-LO!"
      howTo="Guess if the next card is higher or lower"
      detail="+5 × streak · ties count as right"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} deck={deck} />}
      </PlayerPanels>
    </GameScreen>
  );
}
