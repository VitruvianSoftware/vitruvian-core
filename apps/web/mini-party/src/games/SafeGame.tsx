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

// SAFE! — crack the 1–99 combination using −10, −1, +1, +10 and HIGHER / LOWER
// clues. Fewer tries earn more points before a new safe appears.

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
    <rect x="14" y="14" width="92" height="92" rx="18" fill="#4D79FF" />
    <rect x="10" y="30" width="12" height="18" rx="4" fill="#00F2FF" />
    <rect x="10" y="72" width="12" height="18" rx="4" fill="#00F2FF" />
    <circle cx="64" cy="60" r="28" fill="#16213E" />
    <circle cx="64" cy="60" r="18" fill="#FFD700" />
    <path
      d="M64 38 v44 M42 60 h44"
      stroke="#0F0C29"
      strokeWidth="5"
      strokeLinecap="round"
    />
    <circle cx="64" cy="60" r="7" fill="#FFFFFF" />
  </>
);

type Hint = "higher" | "lower" | "open" | null;

function makeSecrets(rand: () => number, count: number): number[] {
  return Array.from({ length: count }, () => randInt(rand, 1, 99));
}

function Board({
  player,
  round,
  secrets,
}: {
  player: Player;
  round: Round;
  secrets: number[];
}) {
  const [safeIdx, setSafeIdx] = useState(0);
  const [guess, setGuess] = useState(50);
  const [tries, setTries] = useState(0);
  const [hint, setHint] = useState<Hint>(null);
  const [bounds, setBounds] = useState<[number, number]>([1, 99]);
  const [lastPts, setLastPts] = useState(0);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const canAct = round.canPlay(player.id) && hint !== "open";
  const secret = secrets[safeIdx % secrets.length];

  const adjust = (delta: number) => {
    if (!canAct) return;
    setGuess((g) => Math.max(1, Math.min(99, g + delta)));
  };

  const submit = () => {
    if (!canAct) return;
    const nextTries = tries + 1;
    setTries(nextTries);

    if (guess === secret) {
      const pts = Math.max(10, 60 - 6 * nextTries);
      round.addScore(player.id, pts);
      setLastPts(pts);
      setHint("open");
      timerRef.current = window.setTimeout(() => {
        setSafeIdx((i) => i + 1);
        setGuess(50);
        setTries(0);
        setHint(null);
        setBounds([1, 99]);
      }, 550);
      return;
    }

    if (guess < secret) {
      setHint("higher");
      setBounds(([lo, hi]) => [Math.max(lo, guess + 1), hi]);
    } else {
      setHint("lower");
      setBounds(([lo, hi]) => [lo, Math.min(hi, guess - 1)]);
    }
  };

  const hintLabel =
    hint === "open"
      ? `OPEN! +${lastPts}`
      : hint === "higher"
        ? "HIGHER ▲"
        : hint === "lower"
          ? "LOWER ▼"
          : "PICK 1–99";

  const hintStyle =
    hint === "open"
      ? "bg-brand-green/25 border-brand-green text-brand-green"
      : hint === "higher"
        ? "bg-brand-cyan/20 border-brand-cyan text-brand-cyan"
        : hint === "lower"
          ? "bg-brand-accent/20 border-brand-accent text-brand-accent"
          : "bg-white/5 border-white/15 text-white/60";

  return (
    <div className="h-full flex flex-col justify-between gap-2 p-2.5 sm:p-4 min-h-0">
      <div className="flex items-center justify-between text-[10px] sm:text-xs font-black uppercase tracking-widest text-white/50 shrink-0">
        <span>
          SAFE #{safeIdx + 1} · TRIES {tries}
        </span>
        {tries > 0 && (
          <span className="px-2 py-0.5 rounded-full bg-white/10 text-white/80 tabular-nums">
            {bounds[0]}–{bounds[1]}
          </span>
        )}
      </div>

      <div className="flex flex-col items-center justify-center gap-2 min-h-0">
        <motion.div
          key={`${safeIdx}-${guess}`}
          initial={{ scale: 0.94 }}
          animate={{ scale: 1 }}
          transition={{ duration: 0.1 }}
          className="px-6 py-2 rounded-2xl bg-brand-bg/90 border-2 border-white/15 text-5xl sm:text-6xl font-black italic tabular-nums shadow-[0_0_20px_#00F2FF22]"
        >
          {guess}
        </motion.div>
        <div
          className={`px-3.5 py-1 rounded-full border text-xs sm:text-sm font-black italic uppercase tracking-wider ${hintStyle}`}
        >
          {hintLabel}
        </div>
      </div>

      <div className="flex flex-col gap-2 shrink-0">
        <div className="grid grid-cols-4 gap-1.5 sm:gap-2">
          {([-10, -1, 1, 10] as const).map((delta) => (
            <ChoiceButton
              key={delta}
              onClick={() => adjust(delta)}
              disabled={!canAct}
              className="py-2 sm:py-2.5 text-lg sm:text-xl tabular-nums"
            >
              {delta > 0 ? `+${delta}` : delta}
            </ChoiceButton>
          ))}
        </div>
        <ChoiceButton
          onClick={submit}
          disabled={!canAct}
          tone={hint === "open" ? "good" : "default"}
          className="w-full py-2.5 sm:py-3 text-xl sm:text-2xl uppercase tracking-wider border-brand-cyan/60 bg-brand-cyan/15 hover:bg-brand-cyan/25"
        >
          TRY
        </ChoiceButton>
      </div>
    </div>
  );
}

export default function SafeGame(props: GameProps) {
  const round = useRound(props, { gameId: "safe", seconds: 30 });
  const secrets = useMemo(() => makeSecrets(round.random(), 50), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="SAFE!"
      howTo="Find the secret number (1–99)"
      detail="Open = 60 − 6 × tries (min 10) · fewer tries = more points"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} secrets={secrets} />}
      </PlayerPanels>
    </GameScreen>
  );
}
