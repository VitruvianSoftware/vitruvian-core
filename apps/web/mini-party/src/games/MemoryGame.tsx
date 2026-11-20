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

// PAIRS! — 4×3 face-down memory grid of 6 coloured shape pairs. Match pairs
// for +10; clear the whole board for +30 and a fresh seeded board.

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
    <rect
      x="14"
      y="20"
      width="56"
      height="74"
      rx="10"
      fill="#4D79FF"
      transform="rotate(-10 42 57)"
    />
    <polygon
      points="42,40 54,57 42,74 30,57"
      fill="#00F2FF"
      transform="rotate(-10 42 57)"
    />
    <rect
      x="48"
      y="22"
      width="56"
      height="76"
      rx="10"
      fill="#FFFFFF"
      transform="rotate(8 76 60)"
    />
    <polygon
      points="76,40 81,53 95,53 84,61 88,74 76,66 64,74 68,61 57,53 71,53"
      fill="#FF0080"
      transform="rotate(8 76 60)"
    />
  </>
);

const PAIR_IDS = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5];

function makeDecks(rand: () => number, count: number): number[][] {
  return Array.from({ length: count }, () => shuffle(rand, PAIR_IDS));
}

function ShapeIcon({ id }: { id: number }) {
  return (
    <svg viewBox="0 0 48 48" className="w-7 h-7 sm:w-9 sm:h-9">
      {id === 0 && <circle cx="24" cy="24" r="15" fill="#FF0080" />}
      {id === 1 && <polygon points="24,6 42,24 24,42 6,24" fill="#00F2FF" />}
      {id === 2 && (
        <polygon
          points="24,6 29,17 41,18 32,27 34,39 24,33 14,39 16,27 7,18 19,17"
          fill="#FFD700"
        />
      )}
      {id === 3 && <polygon points="24,7 41,39 7,39" fill="#4ECCA3" />}
      {id === 4 && (
        <rect x="9" y="9" width="30" height="30" rx="7" fill="#4D79FF" />
      )}
      {id === 5 && (
        <path
          d="M19 8 h10 v11 h11 v10 h-11 v11 h-10 v-11 h-11 v-10 h11 z"
          fill="#FF4D4D"
        />
      )}
    </svg>
  );
}

function Board({
  player,
  round,
  decks,
}: {
  player: Player;
  round: Round;
  decks: number[][];
}) {
  const [deckIdx, setDeckIdx] = useState(0);
  const [matched, setMatched] = useState<boolean[]>(() =>
    Array(12).fill(false),
  );
  const [flipped, setFlipped] = useState<number[]>([]);
  const [busy, setBusy] = useState(false);
  const [banner, setBanner] = useState<"match" | "miss" | "clear" | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const deck = decks[deckIdx % decks.length];
  const canPlay = round.canPlay(player.id);

  const flipCard = (idx: number) => {
    if (!canPlay || busy || matched[idx] || flipped.includes(idx)) return;
    if (flipped.length === 0) {
      setFlipped([idx]);
      return;
    }

    const first = flipped[0];
    if (deck[first] === deck[idx]) {
      const nextMatched = matched.map((v, i) => v || i === first || i === idx);
      setMatched(nextMatched);
      setFlipped([]);
      round.addScore(player.id, 10);

      if (nextMatched.every(Boolean)) {
        round.addScore(player.id, 30);
        setBusy(true);
        setBanner("clear");
        timerRef.current = window.setTimeout(() => {
          setDeckIdx((d) => d + 1);
          setMatched(Array(12).fill(false));
          setFlipped([]);
          setBusy(false);
          setBanner(null);
        }, 450);
      } else {
        setBanner("match");
        timerRef.current = window.setTimeout(() => setBanner(null), 260);
      }
      return;
    }

    setFlipped([first, idx]);
    setBusy(true);
    setBanner("miss");
    timerRef.current = window.setTimeout(() => {
      setFlipped([]);
      setBusy(false);
      setBanner(null);
    }, 600);
  };

  return (
    <div className="h-full flex flex-col items-center justify-center gap-1.5 p-2">
      <div className="shrink-0 h-4 flex items-center justify-center">
        {banner === "clear" && (
          <span className="text-xs font-black italic uppercase text-brand-gold">
            BOARD CLEAR! +30
          </span>
        )}
        {banner === "match" && (
          <span className="text-xs font-black italic uppercase text-brand-green">
            PAIR! +10
          </span>
        )}
        {banner === "miss" && (
          <span className="text-xs font-black italic uppercase text-[#FF4D4D]">
            NO MATCH
          </span>
        )}
      </div>

      <div className="flex-1 min-h-0 w-full flex items-center justify-center">
        <div className="grid grid-cols-4 grid-rows-3 gap-1.5 sm:gap-2 w-full h-full max-w-[240px] max-h-[186px]">
          {deck.map((shapeId, idx) => {
            const isMatched = matched[idx];
            const isFlipped = flipped.includes(idx);
            const faceUp = isMatched || isFlipped;
            const isMiss = isFlipped && banner === "miss";
            return (
              <motion.button
                key={`${deckIdx}-${idx}`}
                type="button"
                disabled={!canPlay || busy || faceUp}
                animate={
                  isMiss ? { x: [0, -4, 4, 0] } : { scale: faceUp ? 1 : 0.97 }
                }
                transition={{ duration: 0.18 }}
                onPointerDown={(e: PointerEvent<HTMLButtonElement>) => {
                  e.preventDefault();
                  flipCard(idx);
                }}
                className={`rounded-xl border-2 flex items-center justify-center cursor-pointer disabled:cursor-default transition-colors ${
                  isMatched
                    ? "bg-brand-green/20 border-brand-green shadow-[0_0_10px_rgba(78,204,163,0.4)]"
                    : isMiss
                      ? "bg-[#FF4D4D]/25 border-[#FF4D4D]"
                      : faceUp
                        ? "bg-brand-card border-brand-cyan shadow-[0_0_12px_rgba(0,242,255,0.35)]"
                        : "bg-white/10 border-white/15 hover:bg-white/15"
                }`}
                aria-label={faceUp ? `Shape ${shapeId + 1}` : "Hidden card"}
              >
                {faceUp ? (
                  <ShapeIcon id={shapeId} />
                ) : (
                  <span className="w-2.5 h-2.5 rounded-full bg-brand-cyan/40" />
                )}
              </motion.button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default function MemoryGame(props: GameProps) {
  const round = useRound(props, { gameId: "memory", seconds: 35 });
  const decks = useMemo(() => makeDecks(round.random(), 12), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="PAIRS!"
      howTo="Flip two cards to match pairs"
      detail="+10 per pair · +30 board clear"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} decks={decks} />}
      </PlayerPanels>
    </GameScreen>
  );
}
