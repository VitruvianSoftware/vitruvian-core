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

// CRACK! — tap when the sweeping needle passes inside the target arc. Hit to
// score +10, reverse direction, speed up, and shrink the arc; miss for −5.

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
    <circle cx="60" cy="60" r="48" fill="#4D79FF" />
    <circle cx="60" cy="60" r="34" fill="#0F0C29" />
    <path
      d="M60 18 A42 42 0 0 1 99 44"
      fill="none"
      stroke="#4ECCA3"
      strokeWidth="12"
      strokeLinecap="round"
    />
    <line
      x1="60"
      y1="60"
      x2="86"
      y2="34"
      stroke="#FFD700"
      strokeWidth="8"
      strokeLinecap="round"
    />
    <circle cx="60" cy="60" r="10" fill="#FF0080" />
  </>
);

function makePins(rand: () => number, count: number): number[] {
  const pins: number[] = [];
  let angle = 90 + rand() * 180;
  for (let i = 0; i < count; i++) {
    pins.push(angle % 360);
    angle = (angle + 85 + rand() * 190) % 360;
  }
  return pins;
}

function angleDiff(a: number, b: number): number {
  return Math.abs(((a - b + 540) % 360) - 180);
}

function polar(cx: number, cy: number, r: number, deg: number) {
  const rad = ((deg - 90) * Math.PI) / 180;
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
}

function arcPath(
  cx: number,
  cy: number,
  r: number,
  startDeg: number,
  endDeg: number,
) {
  const s = polar(cx, cy, r, startDeg);
  const e = polar(cx, cy, r, endDeg);
  const large = endDeg - startDeg > 180 ? 1 : 0;
  return `M ${s.x.toFixed(2)} ${s.y.toFixed(2)} A ${r} ${r} 0 ${large} 1 ${e.x.toFixed(2)} ${e.y.toFixed(2)}`;
}

function Board({
  player,
  round,
  pins,
}: {
  player: Player;
  round: Round;
  pins: number[];
}) {
  const active = round.canPlay(player.id);
  const [angle, setAngle] = useState(0);
  const [level, setLevel] = useState(0);
  const [flash, setFlash] = useState<{ ok: boolean; seq: number } | null>(null);
  const dirRef = useRef(1);
  const angleRef = useRef(0);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const speed = Math.min(340, 135 + level * 16);
  const arcSpan = Math.max(22, 58 - level * 3.2);
  const pinAngle = pins[level % pins.length];

  useFrame(active, (dt) => {
    const next = (angleRef.current + dirRef.current * speed * dt + 360) % 360;
    angleRef.current = next;
    setAngle(next);
  });

  const triggerFlash = (ok: boolean) => {
    if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    setFlash((prev) => ({ ok, seq: (prev?.seq ?? 0) + 1 }));
    timerRef.current = window.setTimeout(() => setFlash(null), ok ? 220 : 280);
  };

  const tap = () => {
    if (!active) return;
    const hit = angleDiff(angleRef.current, pinAngle) <= arcSpan / 2 + 2;
    if (hit) {
      round.addScore(player.id, 10);
      dirRef.current *= -1;
      setLevel((l) => l + 1);
      triggerFlash(true);
    } else {
      round.addScore(player.id, -5);
      triggerFlash(false);
    }
  };

  const needleTip = polar(100, 100, 78, angle);
  const ringBg =
    flash?.ok === true
      ? "bg-brand-green/15"
      : flash?.ok === false
        ? "bg-[#FF4D4D]/25"
        : "";

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        tap();
      }}
      className={`absolute inset-0 flex flex-col items-center justify-center p-3 cursor-pointer transition-colors ${ringBg}`}
      aria-label="Crack lock"
    >
      <motion.div
        key={flash && !flash.ok ? `miss-${flash.seq}` : "dial"}
        animate={flash && !flash.ok ? { x: [0, -8, 8, -5, 5, 0] } : { x: 0 }}
        transition={{ duration: 0.22 }}
        className="relative flex items-center justify-center w-full h-full max-w-[216px] max-h-[216px]"
      >
        <svg viewBox="0 0 200 200" className="w-full h-full overflow-visible">
          <circle
            cx="100"
            cy="100"
            r="74"
            fill="#0F0C29"
            stroke="rgba(255,255,255,0.14)"
            strokeWidth="18"
          />
          <path
            d={arcPath(
              100,
              100,
              74,
              pinAngle - arcSpan / 2,
              pinAngle + arcSpan / 2,
            )}
            fill="none"
            stroke={flash?.ok ? "#FFFFFF" : "#4ECCA3"}
            strokeWidth="18"
            strokeLinecap="round"
            style={{ filter: "drop-shadow(0 0 8px rgba(78,204,163,0.75))" }}
          />
          <line
            x1="100"
            y1="100"
            x2={needleTip.x}
            y2={needleTip.y}
            stroke={flash?.ok === false ? "#FF4D4D" : "#FFD700"}
            strokeWidth="7"
            strokeLinecap="round"
            style={{
              filter: `drop-shadow(0 0 8px ${flash?.ok === false ? "#FF4D4D" : "#FFD700"})`,
            }}
          />
          <circle
            cx="100"
            cy="100"
            r="24"
            fill="#16213E"
            stroke={player.color}
            strokeWidth="4"
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span
            className={`text-xl font-black italic tabular-nums ${
              flash?.ok === true
                ? "text-brand-green"
                : flash?.ok === false
                  ? "text-[#FF4D4D]"
                  : "text-white"
            }`}
          >
            {flash ? (flash.ok ? "+10" : "−5") : level}
          </span>
        </div>
      </motion.div>
    </button>
  );
}

export default function LockGame(props: GameProps) {
  const round = useRound(props, { gameId: "lock", seconds: 25 });
  const pins = useMemo(() => makePins(round.random(), 80), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="CRACK!"
      howTo="Tap when the needle hits the green arc"
      detail="+10 inside arc · −5 outside"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} pins={pins} />}
      </PlayerPanels>
    </GameScreen>
  );
}
