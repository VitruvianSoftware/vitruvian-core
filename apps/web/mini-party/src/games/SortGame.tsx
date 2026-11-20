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

// SORT! — pink circles vs cyan squares appear in the middle; tap the matching
// bin left or right. Right sorts score +5 and speed up the next item; wrong −5.

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

export const sticker = (
  <>
    <path
      d="M52 26 C 36 26, 30 34, 30 48 M22 40 l8 10 8 -10"
      fill="none"
      stroke="#FFD700"
      strokeWidth="7"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M68 26 C 84 26, 90 34, 90 48 M82 40 l8 10 8 -10"
      fill="none"
      stroke="#FFD700"
      strokeWidth="7"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <circle cx="32" cy="82" r="22" fill="#FF0080" />
    <rect x="68" y="60" width="42" height="42" rx="9" fill="#00F2FF" />
  </>
);

type Kind = "pink" | "cyan";

function makeItems(rand: () => number, count: number): Kind[] {
  return Array.from({ length: count }, () => (rand() < 0.5 ? "pink" : "cyan"));
}

function Board({
  player,
  round,
  items,
}: {
  player: Player;
  round: Round;
  items: Kind[];
}) {
  const [index, setIndex] = useState(0);
  const [streak, setStreak] = useState(0);
  const [waiting, setWaiting] = useState(false);
  const [flash, setFlash] = useState<{ side: Kind; ok: boolean } | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const current = items[index % items.length];
  const canTap = round.canPlay(player.id) && !waiting;

  const choose = (side: Kind) => {
    if (!canTap) return;
    const ok = side === current;
    round.addScore(player.id, ok ? 5 : -5);
    const nextStreak = ok ? streak + 1 : 0;
    setStreak(nextStreak);
    setFlash({ side, ok });
    setWaiting(true);

    const delay = ok ? Math.max(40, 220 - nextStreak * 15) : 320;
    timerRef.current = window.setTimeout(() => {
      setFlash(null);
      setWaiting(false);
      setIndex((n) => n + 1);
    }, delay);
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-2.5">
      <div className="shrink-0 h-5 flex items-center justify-center gap-2">
        {flash ? (
          <span
            className={`text-sm font-black italic uppercase ${
              flash.ok ? "text-brand-green" : "text-[#FF4D4D]"
            }`}
          >
            {flash.ok ? "+5!" : "−5!"}
          </span>
        ) : streak >= 2 ? (
          <span className="text-[11px] font-black italic uppercase tracking-wider text-brand-gold">
            STREAK ×{streak}
          </span>
        ) : null}
      </div>

      <div className="flex-1 min-h-0 flex items-center justify-center">
        {!waiting && (
          <motion.div
            key={index}
            initial={{ scale: 0.55, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ duration: 0.1 }}
            className={
              current === "pink"
                ? "w-16 h-16 sm:w-20 sm:h-20 rounded-full bg-[#FF0080] border-4 border-white shadow-[0_0_24px_rgba(255,0,128,0.65)]"
                : "w-16 h-16 sm:w-20 sm:h-20 rounded-2xl bg-[#00F2FF] border-4 border-white shadow-[0_0_24px_rgba(0,242,255,0.65)]"
            }
          />
        )}
      </div>

      <div className="shrink-0 grid grid-cols-2 gap-2.5 w-full max-w-[280px]">
        {(["pink", "cyan"] as const).map((side) => {
          const hit = flash?.side === side;
          const border = hit
            ? flash.ok
              ? "border-brand-green bg-brand-green/25"
              : "border-[#FF4D4D] bg-[#FF4D4D]/25"
            : side === "pink"
              ? "border-[#FF0080]/60 bg-[#FF0080]/15 hover:bg-[#FF0080]/25"
              : "border-[#00F2FF]/60 bg-[#00F2FF]/15 hover:bg-[#00F2FF]/25";
          return (
            <button
              key={side}
              type="button"
              disabled={!canTap}
              onPointerDown={(e) => {
                e.preventDefault();
                choose(side);
              }}
              className={`rounded-2xl border-2 py-3 sm:py-4 flex flex-col items-center justify-center gap-1.5 cursor-pointer active:scale-95 transition-all disabled:cursor-default ${border}`}
              aria-label={side === "pink" ? "Pink bin" : "Cyan bin"}
            >
              <span
                className={
                  side === "pink"
                    ? "w-6 h-6 rounded-full bg-[#FF0080] border-2 border-white"
                    : "w-6 h-6 rounded-md bg-[#00F2FF] border-2 border-white"
                }
              />
              <span className="text-[11px] font-black italic uppercase tracking-wider text-white/90">
                {side === "pink" ? "PINK" : "CYAN"}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default function SortGame(props: GameProps) {
  const round = useRound(props, { gameId: "sort", seconds: 25 });
  const items = useMemo(() => makeItems(round.random(), 180), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="SORT!"
      howTo="Tap the matching bin left or right"
      detail="+5 right (faster!) · −5 wrong"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} items={items} />}
      </PlayerPanels>
    </GameScreen>
  );
}
