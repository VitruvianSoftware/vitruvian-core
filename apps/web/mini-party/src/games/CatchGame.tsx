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

// CATCH! — stars (+5) and bombs (−10) fall in 5 seeded lanes, speeding up
// over time. Tap left or right half of the board to step the basket.

import { useEffect, useMemo, useRef, useState } from "react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useFrame, useRound, type GameProps, type Round } from "../kit/round";
import { randInt } from "../kit/logic";

export const sticker = (
  <>
    <polygon points="46,12 52,26 67,27 56,37 59,52 46,44 33,52 36,37 25,27 40,26" fill="#FFD700" />
    <circle cx="88" cy="40" r="14" fill="#FF4D4D" />
    <path d="M88 26 Q 94 14 104 16" fill="none" stroke="#FFD93D" strokeWidth="5" strokeLinecap="round" />
    <path d="M18 74 H74 L66 106 H26 Z" fill="#00F2FF" />
    <rect x="14" y="68" width="64" height="11" rx="5" fill="#FF0080" />
  </>
);

interface DropSpec {
  id: number;
  spawnTime: number;
  lane: number;
  kind: "star" | "bomb";
  speed: number;
}

interface ActiveDrop {
  id: number;
  lane: number;
  kind: "star" | "bomb";
  speed: number;
  y: number;
}

const LANES = 5;

function makeDrops(rand: () => number): DropSpec[] {
  const out: DropSpec[] = [];
  let t = 0.25;
  let id = 0;
  let lastLane = -1;
  while (t < 24.1) {
    const progress = t / 25;
    const interval = Math.max(0.24, 0.62 - progress * 0.36 + (rand() - 0.5) * 0.08);
    let lane = randInt(rand, 0, LANES - 1);
    if (lane === lastLane && interval < 0.36) lane = randInt(rand, 0, LANES - 1);
    lastLane = lane;
    out.push({
      id: id++,
      spawnTime: t,
      lane,
      kind: rand() < 0.72 ? "star" : "bomb",
      speed: 42 + progress * 42 + rand() * 8,
    });
    t += interval;
  }
  return out;
}

function Board({ player, round, drops }: { player: Player; round: Round; drops: DropSpec[] }) {
  const active = round.canPlay(player.id);
  const [lane, setLane] = useState(2);
  const [falling, setFalling] = useState<ActiveDrop[]>([]);
  const [flash, setFlash] = useState<{ text: string; ok: boolean } | null>(null);
  const [tapSide, setTapSide] = useState<"left" | "right" | null>(null);

  const laneRef = useRef(2);
  const elapsedRef = useRef(0);
  const nextIdxRef = useRef(0);
  const activeDropsRef = useRef<ActiveDrop[]>([]);
  const flashTimerRef = useRef<number | null>(null);
  const tapTimerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (flashTimerRef.current !== null) window.clearTimeout(flashTimerRef.current);
      if (tapTimerRef.current !== null) window.clearTimeout(tapTimerRef.current);
    };
  }, []);

  const triggerFlash = (text: string, ok: boolean) => {
    if (flashTimerRef.current !== null) window.clearTimeout(flashTimerRef.current);
    setFlash({ text, ok });
    flashTimerRef.current = window.setTimeout(() => setFlash(null), 420);
  };

  useFrame(active, (dt) => {
    elapsedRef.current += dt;
    while (nextIdxRef.current < drops.length && drops[nextIdxRef.current].spawnTime <= elapsedRef.current) {
      const spec = drops[nextIdxRef.current++];
      activeDropsRef.current.push({ id: spec.id, lane: spec.lane, kind: spec.kind, speed: spec.speed, y: -6 });
    }

    const kept: ActiveDrop[] = [];
    for (const d of activeDropsRef.current) {
      d.y += d.speed * dt;
      if (d.y >= 80 && d.y <= 94 && d.lane === laneRef.current) {
        round.addScore(player.id, d.kind === "star" ? 5 : -10);
        triggerFlash(d.kind === "star" ? "+5" : "−10", d.kind === "star");
        continue;
      }
      if (d.y <= 104) kept.push(d);
    }
    activeDropsRef.current = kept;
    setFalling([...kept]);
  });

  const move = (dir: -1 | 1) => {
    if (!active) return;
    const next = Math.max(0, Math.min(LANES - 1, laneRef.current + dir));
    laneRef.current = next;
    setLane(next);
    setTapSide(dir === -1 ? "left" : "right");
    if (tapTimerRef.current !== null) window.clearTimeout(tapTimerRef.current);
    tapTimerRef.current = window.setTimeout(() => setTapSide(null), 110);
  };

  return (
    <div className="absolute inset-0 overflow-hidden">
      <div className="absolute inset-0 grid grid-cols-5 pointer-events-none">
        {Array.from({ length: LANES }, (_, i) => (
          <div key={i} className="border-r last:border-r-0 border-white/5" />
        ))}
      </div>

      <button
        type="button"
        onPointerDown={(e) => {
          e.preventDefault();
          move(-1);
        }}
        className={`absolute inset-y-0 left-0 w-1/2 cursor-pointer transition-colors ${tapSide === "left" ? "bg-white/10" : ""}`}
        aria-label="Move basket left"
      >
        <span className="absolute bottom-2 left-2.5 text-xs font-black italic text-white/25">◀</span>
      </button>

      <button
        type="button"
        onPointerDown={(e) => {
          e.preventDefault();
          move(1);
        }}
        className={`absolute inset-y-0 right-0 w-1/2 cursor-pointer transition-colors ${tapSide === "right" ? "bg-white/10" : ""}`}
        aria-label="Move basket right"
      >
        <span className="absolute bottom-2 right-2.5 text-xs font-black italic text-white/25">▶</span>
      </button>

      <div className="pointer-events-none absolute inset-0">
        {falling.map((d) => (
          <div
            key={d.id}
            className="absolute -translate-x-1/2 -translate-y-1/2 w-7 h-7 sm:w-8 sm:h-8 flex items-center justify-center"
            style={{ left: `${d.lane * 20 + 10}%`, top: `${d.y}%` }}
          >
            {d.kind === "star" ? (
              <svg viewBox="0 0 36 36" className="w-full h-full drop-shadow-[0_0_8px_rgba(255,215,0,0.75)]">
                <polygon points="18,3 22,12 32,13 25,20 27,30 18,25 9,30 11,20 4,13 14,12" fill="#FFD700" stroke="#0F0C29" strokeWidth="2.5" />
              </svg>
            ) : (
              <svg viewBox="0 0 36 36" className="w-full h-full drop-shadow-[0_0_8px_rgba(255,77,77,0.75)]">
                <circle cx="18" cy="21" r="11" fill="#FF4D4D" stroke="#0F0C29" strokeWidth="2.5" />
                <path d="M18 10 Q 22 4 27 6" fill="none" stroke="#FFD93D" strokeWidth="3" strokeLinecap="round" />
              </svg>
            )}
          </div>
        ))}

        <div
          className="absolute bottom-[6%] h-[8%] rounded-b-xl rounded-t-md border-2 border-white transition-[left] duration-75"
          style={{
            left: `${lane * 20 + 2}%`,
            width: "16%",
            backgroundColor: flash?.ok === false ? "#FF4D4D" : player.color,
            boxShadow: `0 0 14px ${flash?.ok === false ? "#FF4D4D" : player.color}`,
          }}
        >
          <div className="h-1.5 w-full bg-white/85 rounded-t-sm" />
        </div>

        {flash && (
          <div
            className={`absolute bottom-[16%] -translate-x-1/2 text-base font-black italic uppercase drop-shadow ${flash.ok ? "text-brand-green" : "text-[#FF4D4D]"}`}
            style={{ left: `${lane * 20 + 10}%` }}
          >
            {flash.text}
          </div>
        )}
      </div>
    </div>
  );
}

export default function CatchGame(props: GameProps) {
  const round = useRound(props, { gameId: "catch", seconds: 25 });
  const drops = useMemo(() => makeDrops(round.random()), [round.random]);

  return (
    <GameScreen round={round} players={props.players} title="CATCH!" howTo="Tap left or right half to steer the basket" detail="Stars +5 · bombs −10">
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} drops={drops} />}
      </PlayerPanels>
    </GameScreen>
  );
}
