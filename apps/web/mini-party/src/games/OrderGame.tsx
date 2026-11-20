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

// 1-2-3! — tap numbers 1 through 16 in order on a 4×4 grid. Wrong taps lock
// you out for 1 s; clearing a board scores 50 plus a speed bonus.

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
    <rect x="10" y="10" width="46" height="46" rx="11" fill="#00F2FF" />
    <circle cx="33" cy="33" r="6" fill="#0F0C29" stroke="none" />
    <rect x="64" y="10" width="46" height="46" rx="11" fill="#4ECCA3" />
    <circle cx="78" cy="33" r="5" fill="#0F0C29" stroke="none" />
    <circle cx="96" cy="33" r="5" fill="#0F0C29" stroke="none" />
    <rect x="10" y="64" width="46" height="46" rx="11" fill="#FFD700" />
    <circle cx="24" cy="78" r="4.5" fill="#0F0C29" stroke="none" />
    <circle cx="33" cy="87" r="4.5" fill="#0F0C29" stroke="none" />
    <circle cx="42" cy="96" r="4.5" fill="#0F0C29" stroke="none" />
    <rect x="64" y="64" width="46" height="46" rx="11" fill="#FF0080" />
    <circle cx="78" cy="78" r="4.5" fill="#FFFFFF" stroke="none" />
    <circle cx="96" cy="78" r="4.5" fill="#FFFFFF" stroke="none" />
    <circle cx="78" cy="96" r="4.5" fill="#FFFFFF" stroke="none" />
    <circle cx="96" cy="96" r="4.5" fill="#FFFFFF" stroke="none" />
  </>
);

const NUMBERS = Array.from({ length: 16 }, (_, i) => i + 1);

function makeBoards(rand: () => number, count: number): number[][] {
  return Array.from({ length: count }, () => shuffle(rand, NUMBERS));
}

function Board({
  player,
  round,
  boards,
}: {
  player: Player;
  round: Round;
  boards: number[][];
}) {
  const [boardIdx, setBoardIdx] = useState(0);
  const [next, setNext] = useState(1);
  const [locked, setLocked] = useState(false);
  const [wrongNum, setWrongNum] = useState<number | null>(null);
  const [banner, setBanner] = useState<string | null>(null);
  const boardStartRef = useRef<number>(performance.now());
  const lockTimerRef = useRef<number | null>(null);
  const bannerTimerRef = useRef<number | null>(null);

  useEffect(() => {
    if (round.phase === "playing") {
      boardStartRef.current = performance.now();
    }
  }, [round.phase]);

  useEffect(() => {
    return () => {
      if (lockTimerRef.current !== null)
        window.clearTimeout(lockTimerRef.current);
      if (bannerTimerRef.current !== null)
        window.clearTimeout(bannerTimerRef.current);
    };
  }, []);

  const grid = boards[boardIdx % boards.length];
  const canTap = round.canPlay(player.id) && !locked;

  const pickCell = (num: number) => {
    if (!canTap || num < next) return;
    if (num === next) {
      if (num === 16) {
        const elapsed = (performance.now() - boardStartRef.current) / 1000;
        const speedBonus = Math.round(
          50 * Math.max(0, Math.min(1, (18 - elapsed) / 14)),
        );
        const pts = 50 + speedBonus;
        round.addScore(player.id, pts);
        setBanner(`CLEAR! +${pts}`);
        if (bannerTimerRef.current !== null)
          window.clearTimeout(bannerTimerRef.current);
        bannerTimerRef.current = window.setTimeout(() => setBanner(null), 700);
        setBoardIdx((i) => i + 1);
        setNext(1);
        boardStartRef.current = performance.now();
      } else {
        setNext((n) => n + 1);
      }
      return;
    }

    setLocked(true);
    setWrongNum(num);
    if (lockTimerRef.current !== null)
      window.clearTimeout(lockTimerRef.current);
    lockTimerRef.current = window.setTimeout(() => {
      setLocked(false);
      setWrongNum(null);
    }, 1000);
  };

  return (
    <div className="h-full flex flex-col items-center justify-center gap-1.5 p-2">
      <div className="shrink-0 flex items-center justify-between w-full max-w-[232px] px-1">
        <span className="text-[11px] font-black italic uppercase tracking-wider text-white/60">
          Board {boardIdx + 1}
        </span>
        {banner ? (
          <span className="text-xs font-black italic uppercase text-brand-green">
            {banner}
          </span>
        ) : locked ? (
          <span className="text-xs font-black italic uppercase text-[#FF4D4D] animate-pulse">
            LOCKED 1s!
          </span>
        ) : (
          <span className="text-xs font-black italic uppercase text-brand-cyan">
            NEXT: {next}
          </span>
        )}
      </div>

      <div className="flex-1 min-h-0 w-full flex items-center justify-center">
        <div className="grid grid-cols-4 grid-rows-4 gap-1.5 w-full h-full max-w-[232px] max-h-[232px]">
          {grid.map((num) => {
            const done = num < next;
            const wrong = wrongNum === num;
            return (
              <motion.button
                key={`${boardIdx}-${num}`}
                type="button"
                disabled={!canTap || done}
                animate={wrong ? { x: [0, -6, 6, -4, 4, 0] } : { x: 0 }}
                transition={{ duration: 0.25 }}
                onPointerDown={(e: PointerEvent<HTMLButtonElement>) => {
                  e.preventDefault();
                  pickCell(num);
                }}
                className={`rounded-xl border-2 font-black italic tabular-nums text-base sm:text-xl flex items-center justify-center transition-all active:scale-95 cursor-pointer disabled:cursor-default ${
                  done
                    ? "bg-brand-green/20 border-brand-green/40 text-brand-green/40"
                    : wrong
                      ? "bg-[#FF4D4D]/35 border-[#FF4D4D] text-white shadow-[0_0_12px_rgba(255,77,77,0.6)]"
                      : locked
                        ? "bg-white/5 border-white/10 text-white/35"
                        : "bg-white/10 border-white/15 hover:bg-white/15 text-white shadow-sm"
                }`}
              >
                {num}
              </motion.button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default function OrderGame(props: GameProps) {
  const round = useRound(props, { gameId: "order", seconds: 30 });
  const boards = useMemo(() => makeBoards(round.random(), 12), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="1-2-3!"
      howTo="Tap 1 to 16 in order"
      detail="50 + up to 50 speed bonus per board · wrong = 1s lock"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} boards={boards} />}
      </PlayerPanels>
    </GameScreen>
  );
}
