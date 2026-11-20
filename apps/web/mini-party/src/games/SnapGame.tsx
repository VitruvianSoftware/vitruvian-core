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

// SNAP! — cards flip automatically in a shared sequence. Tap SNAP whenever a
// card matches the previous card in both colour and shape.

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import {
  ChoiceButton,
  GameScreen,
  PlayerPanels,
  useFrame,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { pick, randInt } from "../kit/logic";

export const sticker = (
  <>
    <rect
      x="16"
      y="24"
      width="54"
      height="76"
      rx="11"
      fill="#FFFFFF"
      transform="rotate(-10 43 62)"
    />
    <rect
      x="46"
      y="20"
      width="54"
      height="76"
      rx="11"
      fill="#FFFFFF"
      transform="rotate(8 73 58)"
    />
    <polygon
      points="73,38 78,50 91,50 81,58 84,70 73,63 62,70 65,58 55,50 68,50"
      fill="#FF0080"
    />
    <path
      d="M52 10 l4 -8 M68 10 l6 -6 M36 14 l-4 -8"
      stroke="#FFD700"
      strokeWidth="5"
      strokeLinecap="round"
      fill="none"
    />
  </>
);

type Shape = "circle" | "square" | "triangle" | "star";

interface SnapCard {
  shape: Shape;
  color: string;
}

const SHAPES: readonly Shape[] = ["circle", "square", "triangle", "star"];
const COLORS: readonly string[] = ["#FF0080", "#00F2FF", "#FFD700", "#4ECCA3"];

function ShapeGraphic({
  shape,
  color,
  className,
}: {
  shape: Shape;
  color: string;
  className?: string;
}) {
  return (
    <svg viewBox="0 0 64 64" className={className} aria-hidden="true">
      {shape === "circle" && <circle cx="32" cy="32" r="22" fill={color} />}
      {shape === "square" && (
        <rect x="11" y="11" width="42" height="42" rx="8" fill={color} />
      )}
      {shape === "triangle" && (
        <polygon points="32,8 56,52 8,52" fill={color} strokeLinejoin="round" />
      )}
      {shape === "star" && (
        <polygon
          points="32,6 39,23 58,24 43,36 48,55 32,45 16,55 21,36 6,24 25,23"
          fill={color}
        />
      )}
    </svg>
  );
}

function makeCards(rand: () => number, count: number): SnapCard[] {
  const out: SnapCard[] = [
    { shape: pick(rand, SHAPES), color: pick(rand, COLORS) },
  ];
  let gap = randInt(rand, 4, 6);
  for (let i = 1; i < count; i++) {
    const prev = out[i - 1];
    gap -= 1;
    if (gap <= 0) {
      out.push({ shape: prev.shape, color: prev.color });
      gap = randInt(rand, 4, 6);
      continue;
    }
    let shape = pick(rand, SHAPES);
    let color = pick(rand, COLORS);
    const r = rand();
    if (r < 0.25) {
      color = prev.color;
      shape = pick(
        rand,
        SHAPES.filter((s) => s !== prev.shape),
      );
    } else if (r < 0.5) {
      shape = prev.shape;
      color = pick(
        rand,
        COLORS.filter((c) => c !== prev.color),
      );
    } else if (shape === prev.shape && color === prev.color) {
      shape = pick(
        rand,
        SHAPES.filter((s) => s !== prev.shape),
      );
    }
    out.push({ shape, color });
  }
  return out;
}

function Board({
  player,
  round,
  cards,
}: {
  player: Player;
  round: Round;
  cards: SnapCard[];
}) {
  const [index, setIndex] = useState(0);
  const [progress, setProgress] = useState(0);
  const [snapped, setSnapped] = useState(false);
  const [feedback, setFeedback] = useState<{
    ok: boolean;
    text: string;
  } | null>(null);
  const indexRef = useRef(0);
  const timerRef = useRef(0);
  const snappedIdxRef = useRef(-1);
  const flashTimer = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (flashTimer.current !== null) window.clearTimeout(flashTimer.current);
    };
  }, []);

  const active = round.canPlay(player.id);

  useFrame(active, (dt) => {
    const interval = Math.max(0.48, 0.9 - indexRef.current * 0.012);
    timerRef.current += dt;
    if (timerRef.current >= interval) {
      timerRef.current -= interval;
      indexRef.current += 1;
      setIndex(indexRef.current);
      setSnapped(false);
    }
    setProgress(Math.min(1, timerRef.current / interval));
  });

  const snap = () => {
    if (!active) return;
    const curIdx = indexRef.current;
    const cur = cards[curIdx % cards.length];
    const prev = curIdx > 0 ? cards[(curIdx - 1) % cards.length] : null;
    const isMatch =
      prev !== null && cur.color === prev.color && cur.shape === prev.shape;

    if (isMatch) {
      if (snappedIdxRef.current === curIdx) return;
      snappedIdxRef.current = curIdx;
      setSnapped(true);
      round.addScore(player.id, 15);
      setFeedback({ ok: true, text: "SNAP! +15" });
    } else {
      round.addScore(player.id, -10);
      setFeedback({ ok: false, text: "NOPE! −10" });
    }
    if (flashTimer.current !== null) window.clearTimeout(flashTimer.current);
    flashTimer.current = window.setTimeout(() => setFeedback(null), 380);
  };

  const curCard = cards[index % cards.length];
  const prevCard = index > 0 ? cards[(index - 1) % cards.length] : null;

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-3 min-h-0">
      <div className="relative flex-1 min-h-0 w-full flex items-center justify-center gap-3">
        <div className="flex flex-col items-center gap-1 opacity-55">
          <span className="text-[9px] font-black uppercase tracking-widest text-white/60">
            Prev
          </span>
          <div className="w-14 h-20 sm:w-16 sm:h-24 rounded-xl border-2 border-white/25 bg-white/90 flex items-center justify-center">
            {prevCard ? (
              <ShapeGraphic
                shape={prevCard.shape}
                color={prevCard.color}
                className="w-9 h-9 sm:w-10 sm:h-10"
              />
            ) : (
              <span className="text-[10px] font-black text-brand-bg/40">—</span>
            )}
          </div>
        </div>

        <div className="flex flex-col items-center gap-1">
          <span className="text-[9px] font-black uppercase tracking-widest text-brand-cyan">
            Now
          </span>
          <motion.div
            key={index}
            initial={{ scale: 0.85, rotate: -4 }}
            animate={{ scale: 1, rotate: 0 }}
            transition={{ duration: 0.12 }}
            className={`w-24 h-32 sm:w-28 sm:h-36 rounded-2xl border-4 bg-white flex items-center justify-center shadow-[0_10px_24px_rgba(0,0,0,0.45)] ${
              feedback
                ? feedback.ok
                  ? "border-brand-green shadow-[0_0_24px_rgba(78,204,163,0.75)]"
                  : "border-brand-accent shadow-[0_0_24px_rgba(255,0,128,0.75)]"
                : "border-white"
            }`}
          >
            <ShapeGraphic
              shape={curCard.shape}
              color={curCard.color}
              className="w-16 h-16 sm:w-20 sm:h-20"
            />
          </motion.div>
        </div>

        {feedback && (
          <div
            className={`absolute top-0 px-3 py-1 rounded-full text-xs font-black italic uppercase shadow-lg ${
              feedback.ok
                ? "bg-brand-green text-brand-bg"
                : "bg-brand-accent text-white"
            }`}
          >
            {feedback.text}
          </div>
        )}
      </div>

      <div className="w-full max-w-[230px] h-1.5 rounded-full bg-white/10 overflow-hidden shrink-0">
        <div
          className="h-full bg-brand-cyan"
          style={{ width: `${(1 - progress) * 100}%` }}
        />
      </div>

      <ChoiceButton
        onClick={snap}
        disabled={!active || snapped}
        tone={feedback ? (feedback.ok ? "good" : "bad") : "default"}
        className="w-full max-w-[230px] py-3.5 text-2xl sm:text-3xl bg-brand-accent/25 border-brand-accent hover:bg-brand-accent/35 shrink-0"
      >
        {snapped ? "SNAPPED!" : "SNAP!"}
      </ChoiceButton>
    </div>
  );
}

export default function SnapGame(props: GameProps) {
  const round = useRound(props, { gameId: "snap", seconds: 25 });
  const cards = useMemo(() => makeCards(round.random(), 80), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="SNAP!"
      howTo="Tap SNAP when a card matches the one before"
      detail="+15 match · −10 miss · same colour & shape"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} cards={cards} />}
      </PlayerPanels>
    </GameScreen>
  );
}
