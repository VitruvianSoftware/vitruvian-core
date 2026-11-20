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

// PUSH! — push-your-luck dice. Roll to build up a pot, then bank it before
// rolling a 1 wipes the pot. 6 turns max within the 30-second cap.

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
    <path
      d="M16 32 L28 24 M12 52 L24 50"
      stroke="#FFD700"
      strokeWidth="6"
      strokeLinecap="round"
    />
    <rect
      x="26"
      y="24"
      width="70"
      height="70"
      rx="16"
      fill="#FFFFFF"
      transform="rotate(-12 61 59)"
    />
    <g transform="rotate(-12 61 59)">
      <circle cx="43" cy="41" r="6" fill="#0F0C29" />
      <circle cx="79" cy="41" r="6" fill="#0F0C29" />
      <circle cx="61" cy="59" r="7" fill="#FF0080" />
      <circle cx="43" cy="77" r="6" fill="#0F0C29" />
      <circle cx="79" cy="77" r="6" fill="#0F0C29" />
    </g>
  </>
);

const MAX_TURNS = 6;
const PIPS: Record<number, readonly [number, number][]> = {
  1: [[50, 50]],
  2: [
    [28, 28],
    [72, 72],
  ],
  3: [
    [28, 28],
    [50, 50],
    [72, 72],
  ],
  4: [
    [28, 28],
    [72, 28],
    [28, 72],
    [72, 72],
  ],
  5: [
    [28, 28],
    [72, 28],
    [50, 50],
    [28, 72],
    [72, 72],
  ],
  6: [
    [28, 26],
    [72, 26],
    [28, 50],
    [72, 50],
    [28, 74],
    [72, 74],
  ],
};

function makeRolls(rand: () => number, count: number): number[] {
  return Array.from({ length: count }, () => randInt(rand, 1, 6));
}

function DieFace({ value }: { value: number | null }) {
  const pips = value ? PIPS[value] : [];
  return (
    <svg viewBox="0 0 100 100" className="w-16 h-16 sm:w-20 sm:h-20">
      <rect
        x="6"
        y="6"
        width="88"
        height="88"
        rx="18"
        fill={value === 1 ? "#FFE5E5" : "#FFFFFF"}
        stroke="#0F0C29"
        strokeWidth="5"
      />
      {pips.map(([cx, cy], idx) => (
        <circle
          key={idx}
          cx={cx}
          cy={cy}
          r={value === 1 ? 11 : 8.5}
          fill={value === 1 ? "#FF4D4D" : "#0F0C29"}
        />
      ))}
      {value === null && (
        <circle cx="50" cy="50" r="10" fill="#0F0C29" opacity="0.2" />
      )}
    </svg>
  );
}

function Board({
  player,
  round,
  rolls,
}: {
  player: Player;
  round: Round;
  rolls: number[];
}) {
  const [turn, setTurn] = useState(0);
  const [cursor, setCursor] = useState(0);
  const [pot, setPot] = useState(0);
  const [die, setDie] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [banner, setBanner] = useState<{
    text: string;
    tone: "good" | "bad";
  } | null>(null);
  const totalRef = useRef(0);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const canAct = round.canPlay(player.id) && !busy;

  const roll = () => {
    if (!canAct) return;
    const value = rolls[cursor % rolls.length];
    setCursor((c) => c + 1);
    setDie(value);
    if (value === 1) {
      setPot(0);
      setBusy(true);
      setBanner({ text: "BUST! POT LOST", tone: "bad" });
      timerRef.current = window.setTimeout(() => {
        if (turn + 1 >= MAX_TURNS) round.finish(player.id);
        else {
          setTurn((t) => t + 1);
          setBanner(null);
          setBusy(false);
        }
      }, 480);
      return;
    }
    setPot((p) => p + value);
    setBanner(null);
  };

  const bank = () => {
    if (!canAct || pot <= 0) return;
    const banked = pot;
    const nextTotal = totalRef.current + banked;
    totalRef.current = nextTotal;
    round.addScore(player.id, banked);
    setPot(0);
    setBusy(true);
    setBanner({ text: `BANKED +${banked}!`, tone: "good" });
    timerRef.current = window.setTimeout(
      () => {
        if (turn + 1 >= MAX_TURNS) round.finish(player.id, nextTotal);
        else {
          setTurn((t) => t + 1);
          setBanner(null);
          setBusy(false);
        }
      },
      turn + 1 >= MAX_TURNS ? 300 : 360,
    );
  };

  return (
    <div className="h-full flex flex-col justify-between gap-2 p-2.5 sm:p-4 min-h-0">
      <div className="flex items-center justify-between gap-2 shrink-0">
        <span className="text-[10px] sm:text-xs font-black uppercase tracking-widest text-white/50">
          TURN {turn + 1}/{MAX_TURNS}
        </span>
        <div className="flex items-center gap-1.5">
          {Array.from({ length: MAX_TURNS }, (_, i) => (
            <span
              key={i}
              className={`w-2.5 h-2.5 rounded-full ${
                i < turn
                  ? "bg-brand-green"
                  : i === turn
                    ? "bg-brand-gold shadow-[0_0_8px_#FFD700]"
                    : "bg-white/15"
              }`}
            />
          ))}
        </div>
      </div>

      <div className="flex flex-col items-center justify-center gap-2 min-h-0">
        <motion.div
          key={cursor}
          initial={{ rotate: -18, scale: 0.85 }}
          animate={{ rotate: 0, scale: 1 }}
          transition={{ type: "spring", stiffness: 450, damping: 22 }}
          className="drop-shadow-[0_0_16px_#00F2FF33]"
        >
          <DieFace value={die} />
        </motion.div>
        <div className="px-4 py-1 rounded-full bg-brand-bg/90 border border-white/15 text-lg sm:text-xl font-black italic tabular-nums text-brand-gold">
          POT +{pot}
        </div>
        <div className="h-6 flex items-center justify-center">
          {banner && (
            <span
              className={`text-sm sm:text-base font-black italic uppercase tracking-wider ${banner.tone === "good" ? "text-brand-green" : "text-[#FF4D4D]"}`}
            >
              {banner.text}
            </span>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 shrink-0">
        <ChoiceButton
          onClick={roll}
          disabled={!canAct}
          className="py-3 text-lg sm:text-2xl uppercase border-brand-cyan/60 bg-brand-cyan/15 hover:bg-brand-cyan/25"
        >
          ROLL
        </ChoiceButton>
        <ChoiceButton
          onClick={bank}
          disabled={!canAct || pot <= 0}
          tone="good"
          className="py-3 text-lg sm:text-2xl uppercase"
        >
          BANK (+{pot})
        </ChoiceButton>
      </div>
    </div>
  );
}

export default function DiceGame(props: GameProps) {
  const round = useRound(props, { gameId: "dice", seconds: 30 });
  const rolls = useMemo(() => makeRolls(round.random(), 240), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="PUSH!"
      howTo="Roll to build the pot — bank before rolling a 1"
      detail="Roll a 1 and lose the pot · 6 turns max"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} rolls={rolls} />}
      </PlayerPanels>
    </GameScreen>
  );
}
