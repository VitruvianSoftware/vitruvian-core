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

// GREEN! — sprint down the track while the light is green; freeze before it
// turns red. First to 60 taps finishes early with a time bonus.

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import {
  GameScreen,
  PlayerPanels,
  useFrame,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";

export const sticker = (
  <>
    <rect x="34" y="10" width="52" height="100" rx="14" fill="#16213E" />
    <circle cx="60" cy="30" r="11" fill="#FF4D4D" />
    <circle cx="60" cy="60" r="11" fill="#FFD93D" />
    <circle cx="60" cy="90" r="12" fill="#4ECCA3" />
    <path
      d="M14 44 h12 M10 60 h16 M14 76 h12"
      stroke="#00F2FF"
      strokeWidth="6"
      strokeLinecap="round"
    />
  </>
);

type Light = "green" | "yellow" | "red";
interface Segment {
  end: number;
  light: Light;
}

const TARGET = 60;
const LAMPS: { kind: Light; active: string; dim: string }[] = [
  {
    kind: "red",
    active: "bg-[#FF4D4D] shadow-[0_0_12px_#FF4D4D]",
    dim: "bg-[#FF4D4D]/20",
  },
  {
    kind: "yellow",
    active: "bg-[#FFD93D] shadow-[0_0_12px_#FFD93D]",
    dim: "bg-[#FFD93D]/20",
  },
  {
    kind: "green",
    active: "bg-brand-green shadow-[0_0_12px_#4ECCA3]",
    dim: "bg-brand-green/20",
  },
];

function makeSchedule(rand: () => number, totalSec = 35): Segment[] {
  const segs: Segment[] = [];
  let t = 0;
  while (t < totalSec) {
    t += 1.0 + rand() * 2.0;
    segs.push({ end: t, light: "green" });
    t += 0.3;
    segs.push({ end: t, light: "yellow" });
    t += 0.8 + rand() * 1.2;
    segs.push({ end: t, light: "red" });
  }
  return segs;
}

function lightAt(schedule: readonly Segment[], elapsed: number): Light {
  for (const seg of schedule) {
    if (elapsed < seg.end) return seg.light;
  }
  return "green";
}

function Board({
  player,
  round,
  light,
}: {
  player: Player;
  round: Round;
  light: Light;
}) {
  const [progress, setProgress] = useState(0);
  const progressRef = useRef(0);
  const [flash, setFlash] = useState<"good" | "bad" | null>(null);
  const timerRef = useRef<number | null>(null);
  const active = round.canPlay(player.id);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const triggerFlash = (kind: "good" | "bad", ms: number) => {
    if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    setFlash(kind);
    timerRef.current = window.setTimeout(() => {
      setFlash(null);
      timerRef.current = null;
    }, ms);
  };

  const tap = () => {
    if (!active || progressRef.current >= TARGET) return;
    if (light === "red") {
      const next = Math.max(0, progressRef.current - 5);
      progressRef.current = next;
      setProgress(next);
      round.setScore(player.id, next);
      triggerFlash("bad", 260);
      return;
    }
    const next = Math.min(TARGET, progressRef.current + 1);
    progressRef.current = next;
    setProgress(next);
    triggerFlash("good", 100);
    if (next >= TARGET) {
      round.finish(player.id, Math.round(100 + round.timeLeft * 5));
    } else {
      round.setScore(player.id, next);
    }
  };

  const pct = (progress / TARGET) * 100;
  const label =
    light === "green" ? "GO!" : light === "yellow" ? "WAIT..." : "STOP!";
  const labelColor =
    light === "green"
      ? "text-brand-green"
      : light === "yellow"
        ? "text-[#FFD93D]"
        : "text-[#FF4D4D]";

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        tap();
      }}
      className={`absolute inset-0 flex flex-col justify-between p-3 sm:p-4 touch-none cursor-pointer transition-colors ${
        flash === "bad"
          ? "bg-[#FF4D4D]/25"
          : flash === "good"
            ? "bg-brand-green/10"
            : ""
      }`}
      aria-label="Tap to run"
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-brand-bg/90 border border-white/10">
          {LAMPS.map((l) => (
            <span
              key={l.kind}
              className={`w-3.5 h-3.5 rounded-full transition-all ${light === l.kind ? l.active : l.dim}`}
            />
          ))}
          <span
            className={`text-sm sm:text-base font-black italic uppercase ml-1 ${labelColor}`}
          >
            {label}
          </span>
        </div>
        <div className="text-lg sm:text-xl font-black italic tabular-nums">
          {progress}
          <span className="text-xs opacity-50 not-italic"> / {TARGET}</span>
        </div>
      </div>

      <div className="relative w-full h-11 sm:h-14 rounded-2xl bg-brand-bg/90 border-2 border-white/15 overflow-hidden flex items-center">
        <motion.div
          className="h-full rounded-r-xl"
          animate={{ width: `${pct}%` }}
          transition={{ type: "spring", stiffness: 450, damping: 32 }}
          style={{
            backgroundColor: flash === "bad" ? "#FF4D4D" : player.color,
            boxShadow: `0 0 18px ${flash === "bad" ? "#FF4D4D88" : `${player.color}88`}`,
          }}
        />
        <div
          className="absolute right-0 inset-y-0 w-3 opacity-80"
          style={{
            backgroundImage:
              "repeating-linear-gradient(0deg, #fff 0 6px, #0F0C29 6px 12px)",
          }}
        />
        {flash === "bad" && (
          <motion.span
            initial={{ scale: 0.7, opacity: 0 }}
            animate={{ scale: 1.1, opacity: 1 }}
            className="absolute inset-0 flex items-center justify-center text-2xl font-black italic text-white drop-shadow"
          >
            −5!
          </motion.span>
        )}
      </div>

      <motion.div
        animate={{ scale: flash === "good" ? 0.97 : 1 }}
        transition={{ duration: 0.08 }}
        className={`w-full py-2.5 rounded-2xl border-2 text-center font-black italic uppercase text-sm sm:text-base tracking-wider ${
          light === "red"
            ? "border-[#FF4D4D]/60 bg-[#FF4D4D]/15 text-[#FF4D4D]"
            : "border-brand-green/60 bg-brand-green/15 text-brand-green"
        }`}
      >
        {light === "red" ? "HOLD STILL!" : "TAP ANYWHERE TO RUN!"}
      </motion.div>
    </button>
  );
}

export default function GreenGame(props: GameProps) {
  const round = useRound(props, { gameId: "green", seconds: 30 });
  const schedule = useMemo(() => makeSchedule(round.random()), [round.random]);
  const elapsedRef = useRef(0);
  const [light, setLight] = useState<Light>("green");

  useEffect(() => {
    if (round.phase === "intro") {
      elapsedRef.current = 0;
      setLight("green");
    }
  }, [round.phase]);

  useFrame(round.phase === "playing", (dt) => {
    elapsedRef.current += dt;
    const next = lightAt(schedule, elapsedRef.current);
    setLight((prev) => (prev === next ? prev : next));
  });

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="GREEN!"
      howTo="Tap fast on GREEN — freeze on RED"
      detail="First to 60 gets 100 + time bonus · red tap = −5"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} light={light} />}
      </PlayerPanels>
    </GameScreen>
  );
}
