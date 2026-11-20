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

// WHEEL! — an 8-wedge prize wheel spins fast; tap to brake over ~1.5 s with
// slight seeded randomness and collect the wedge under the pointer (4 spins).

import { useEffect, useMemo, useRef, useState } from "react";
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
    <circle cx="60" cy="64" r="44" fill="#4D79FF" />
    <path d="M60 64 L60 20 A44 44 0 0 1 91 33 Z" fill="#FFD700" />
    <path d="M60 64 L91 33 A44 44 0 0 1 104 64 Z" fill="#4ECCA3" />
    <path d="M60 64 L60 108 A44 44 0 0 1 29 95 Z" fill="#FF4D4D" />
    <path d="M60 64 L16 64 A44 44 0 0 1 60 20 Z" fill="#00F2FF" />
    <circle cx="60" cy="64" r="11" fill="#FFFFFF" />
    <polygon points="60,26 48,6 72,6" fill="#FF0080" />
  </>
);

interface WedgeDef {
  value: number;
  label: string;
  span: number;
  color: string;
  text: string;
  start: number;
  end: number;
}

const RAW_WEDGES = [
  { value: 100, label: "100", span: 24, color: "#FFD700", text: "#0F0C29" },
  { value: 10, label: "10", span: 58, color: "#4D79FF", text: "#FFFFFF" },
  { value: 50, label: "50", span: 42, color: "#4ECCA3", text: "#0F0C29" },
  { value: 20, label: "20", span: 52, color: "#00F2FF", text: "#0F0C29" },
  { value: 100, label: "100", span: 24, color: "#FFD700", text: "#0F0C29" },
  { value: 10, label: "10", span: 58, color: "#4D79FF", text: "#FFFFFF" },
  { value: 0, label: "BUST", span: 50, color: "#FF4D4D", text: "#FFFFFF" },
  { value: 20, label: "20", span: 52, color: "#00F2FF", text: "#0F0C29" },
] as const;

const WEDGES: WedgeDef[] = (() => {
  let acc = 0;
  return RAW_WEDGES.map((w) => {
    const start = acc;
    acc += w.span;
    return { ...w, start, end: acc };
  });
})();

const SPINS_PER_PLAYER = 4;

interface SpinSpec {
  startAngle: number;
  speed: number;
  brakeSec: number;
  jitter: number;
}

function makeSpins(rand: () => number): SpinSpec[] {
  return Array.from({ length: SPINS_PER_PLAYER }, (_, i) => ({
    startAngle: rand() * 360,
    speed: 420 + i * 45 + rand() * 80,
    brakeSec: 1.35 + rand() * 0.35,
    jitter: (rand() - 0.5) * 90,
  }));
}

function polar(cx: number, cy: number, r: number, deg: number) {
  const rad = ((deg - 90) * Math.PI) / 180;
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
}

function wedgePath(startDeg: number, endDeg: number): string {
  const s = polar(100, 100, 86, startDeg);
  const e = polar(100, 100, 86, endDeg);
  return `M 100 100 L ${s.x.toFixed(2)} ${s.y.toFixed(2)} A 86 86 0 ${endDeg - startDeg > 180 ? 1 : 0} 1 ${e.x.toFixed(2)} ${e.y.toFixed(2)} Z`;
}

function wedgeAt(angle: number): WedgeDef {
  const local = ((-angle % 360) + 360) % 360;
  return (
    WEDGES.find((w) => local >= w.start && local < w.end) ??
    WEDGES[WEDGES.length - 1]
  );
}

function Board({
  player,
  round,
  spins,
}: {
  player: Player;
  round: Round;
  spins: SpinSpec[];
}) {
  const active = round.canPlay(player.id);
  const [spinIdx, setSpinIdx] = useState(0);
  const [angle, setAngle] = useState(() => spins[0]?.startAngle ?? 0);
  const [stage, setStage] = useState<"spinning" | "braking" | "landed">(
    "spinning",
  );
  const [landed, setLanded] = useState<WedgeDef | null>(null);
  const sim = useRef({
    angle: spins[0]?.startAngle ?? 0,
    stage: "spinning" as "spinning" | "braking" | "landed",
    brakeElapsed: 0,
    brakeStart: 0,
    brakeEnd: 0,
    spinIdx: 0,
  });
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  useFrame(active && stage !== "landed", (dt) => {
    const s = sim.current;
    const spec = spins[s.spinIdx];
    if (!spec) return;

    if (s.stage === "spinning") {
      s.angle = (s.angle + spec.speed * dt) % 360;
      setAngle(s.angle);
      return;
    }

    if (s.stage === "braking") {
      s.brakeElapsed += dt;
      const u = Math.min(1, s.brakeElapsed / spec.brakeSec);
      s.angle = s.brakeStart + (s.brakeEnd - s.brakeStart) * (1 - (1 - u) ** 3);
      setAngle(s.angle);

      if (u >= 1) {
        s.stage = "landed";
        setStage("landed");
        const hit = wedgeAt(s.angle);
        setLanded(hit);
        round.addScore(player.id, hit.value);

        const doneAll = s.spinIdx + 1 >= SPINS_PER_PLAYER;
        timerRef.current = window.setTimeout(() => {
          if (doneAll) {
            round.finish(player.id);
            return;
          }
          const nextIdx = s.spinIdx + 1;
          s.spinIdx = nextIdx;
          s.angle = spins[nextIdx].startAngle;
          s.stage = "spinning";
          setSpinIdx(nextIdx);
          setAngle(s.angle);
          setStage("spinning");
          setLanded(null);
        }, 850);
      }
    }
  });

  const brake = () => {
    const s = sim.current;
    if (!active || s.stage !== "spinning") return;
    const spec = spins[s.spinIdx];
    s.stage = "braking";
    s.brakeElapsed = 0;
    s.brakeStart = s.angle;
    s.brakeEnd = s.angle + (spec.speed * spec.brakeSec) / 3 + spec.jitter;
    setStage("braking");
  };

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        brake();
      }}
      className="absolute inset-0 flex flex-col items-center justify-center gap-1.5 p-2 cursor-pointer"
      aria-label="Brake wheel"
    >
      <div className="flex-1 min-h-0 w-full flex items-center justify-center">
        <svg
          viewBox="0 0 200 200"
          className="w-full h-full max-w-[208px] max-h-[208px]"
        >
          <g transform={`rotate(${angle} 100 100)`}>
            {WEDGES.map((w, idx) => (
              <g key={idx}>
                <path
                  d={wedgePath(w.start, w.end)}
                  fill={w.color}
                  stroke="#0F0C29"
                  strokeWidth="3"
                />
                <text
                  x="100"
                  y="38"
                  textAnchor="middle"
                  dominantBaseline="central"
                  fill={w.text}
                  fontSize={w.value === 0 ? "11" : "13"}
                  fontWeight="900"
                  fontStyle="italic"
                  transform={`rotate(${(w.start + w.end) / 2} 100 100)`}
                >
                  {w.label}
                </text>
              </g>
            ))}
            <circle
              cx="100"
              cy="100"
              r="86"
              fill="none"
              stroke="#FFFFFF"
              strokeWidth="3"
            />
          </g>
          <circle
            cx="100"
            cy="100"
            r="20"
            fill="#0F0C29"
            stroke={player.color}
            strokeWidth="4"
          />
          <text
            x="100"
            y="101"
            textAnchor="middle"
            dominantBaseline="central"
            fill="#FFFFFF"
            fontSize="12"
            fontWeight="900"
            fontStyle="italic"
          >
            {spinIdx + 1}/{SPINS_PER_PLAYER}
          </text>
          <polygon
            points="100,24 90,4 110,4"
            fill="#FF0080"
            stroke="#FFFFFF"
            strokeWidth="2.5"
            strokeLinejoin="round"
          />
        </svg>
      </div>

      <div className="shrink-0 h-6 flex items-center justify-center">
        {landed ? (
          <span
            className="text-sm font-black italic uppercase"
            style={{ color: landed.value === 0 ? "#FF4D4D" : "#4ECCA3" }}
          >
            {landed.value === 0 ? "BUST! +0" : `+${landed.value}!`}
          </span>
        ) : (
          <span className="text-[11px] font-black italic uppercase tracking-wider text-brand-cyan">
            {stage === "spinning" ? "TAP TO BRAKE!" : "SLOWING..."}
          </span>
        )}
      </div>
    </button>
  );
}

export default function WheelGame(props: GameProps) {
  const round = useRound(props, { gameId: "wheel", seconds: 30 });
  const spins = useMemo(() => makeSpins(round.random()), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="WHEEL!"
      howTo="Tap to brake the wheel under the pointer"
      detail="4 spins per player · two small 100s, one BUST"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} spins={spins} />}
      </PlayerPanels>
    </GameScreen>
  );
}
