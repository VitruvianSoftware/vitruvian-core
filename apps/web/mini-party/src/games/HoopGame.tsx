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

// HOOP! — tap when the moving power bar hits the sweet spot to sink a swish.
// Each shot moves the basket to a new seeded distance and speeds up the bar.

import { useMemo, useRef, useState } from "react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useFrame, useRound, type GameProps, type Round } from "../kit/round";
import { randInt } from "../kit/logic";

export const sticker = (
  <>
    <rect x="82" y="20" width="14" height="44" rx="4" fill="#FFFFFF" />
    <rect x="52" y="48" width="32" height="8" rx="4" fill="#FF0080" />
    <path d="M55 56 L59 78 H77 L81 56" stroke="#00F2FF" strokeWidth="4" fill="none" />
    <circle cx="32" cy="36" r="18" fill="#FFD700" />
    <path d="M18 36 H46 M32 22 V50" stroke="#0F0C29" strokeWidth="3" fill="none" />
  </>
);

interface Shot {
  hoopX: number;
  targetPower: number;
  tolerance: number;
  speed: number;
}

type ShotResult = "swish" | "short" | "long";

interface SimState {
  mode: "aim" | "fly" | "land";
  shotIdx: number;
  power: number;
  dir: number;
  flightT: number;
  pauseT: number;
  shotPower: number;
  result: ShotResult | null;
}

function makeShots(rand: () => number, count: number): Shot[] {
  const shots: Shot[] = [];
  let prevX = -1;
  for (let i = 0; i < count; i++) {
    let hoopX = randInt(rand, 118, 204);
    if (prevX >= 0 && Math.abs(hoopX - prevX) < 18) {
      hoopX = prevX > 160 ? randInt(rand, 118, 148) : randInt(rand, 170, 204);
    }
    prevX = hoopX;
    shots.push({
      hoopX,
      targetPower: 0.22 + ((hoopX - 118) / 86) * 0.62,
      tolerance: Math.max(0.058, 0.095 - i * 0.003),
      speed: Math.min(2.6, 1.05 + i * 0.14),
    });
  }
  return shots;
}

function bezier(p0: number, p1: number, p2: number, t: number): number {
  const m = 1 - t;
  return m * m * p0 + 2 * m * t * p1 + t * t * p2;
}

function ballPos(sim: SimState, shot: Shot): { x: number; y: number } {
  if (sim.mode === "aim" || !sim.result) return { x: 28, y: 102 };
  const t = Math.min(1, sim.flightT);
  if (sim.result === "swish") {
    if (t <= 0.78) {
      const u = t / 0.78;
      return { x: bezier(28, (28 + shot.hoopX) / 2, shot.hoopX, u), y: bezier(102, -26, 58, u) };
    }
    return { x: shot.hoopX, y: 58 + ((t - 0.78) / 0.22) * 36 };
  }
  if (sim.result === "short") {
    const ratio = Math.max(0.28, sim.shotPower / shot.targetPower);
    const endX = Math.max(48, Math.min(shot.hoopX - 20, 28 + (shot.hoopX - 28) * ratio));
    return { x: bezier(28, (28 + endX) / 2, endX, t), y: bezier(102, 16, 112, t) };
  }
  const over = Math.max(0.05, sim.shotPower - shot.targetPower);
  const endX = Math.min(228, Math.max(shot.hoopX + 20, shot.hoopX + 20 + over * 70));
  return { x: bezier(28, (28 + endX) / 2, endX, t), y: bezier(102, -26, 112, t) };
}

const INITIAL_SIM: SimState = {
  mode: "aim",
  shotIdx: 0,
  power: 0,
  dir: 1,
  flightT: 0,
  pauseT: 0,
  shotPower: 0,
  result: null,
};

function Board({ player, round, shots }: { player: Player; round: Round; shots: Shot[] }) {
  const simRef = useRef<SimState>({ ...INITIAL_SIM });
  const [view, setView] = useState<SimState>(INITIAL_SIM);
  const active = round.canPlay(player.id);

  useFrame(active, (dt) => {
    const s = simRef.current;
    const shot = shots[s.shotIdx % shots.length];
    if (s.mode === "aim") {
      s.power += s.dir * shot.speed * dt;
      if (s.power >= 1) {
        s.power = 1;
        s.dir = -1;
      } else if (s.power <= 0) {
        s.power = 0;
        s.dir = 1;
      }
    } else if (s.mode === "fly") {
      s.flightT = Math.min(1, s.flightT + dt / 0.58);
      if (s.flightT >= 1) {
        if (s.result === "swish") round.addScore(player.id, 20);
        s.mode = "land";
        s.pauseT = 0.48;
      }
    } else {
      s.pauseT -= dt;
      if (s.pauseT <= 0) {
        Object.assign(s, INITIAL_SIM, { shotIdx: s.shotIdx + 1 });
      }
    }
    setView({ ...s });
  });

  const shoot = () => {
    const s = simRef.current;
    if (!active || s.mode !== "aim") return;
    const shot = shots[s.shotIdx % shots.length];
    const diff = s.power - shot.targetPower;
    s.result = Math.abs(diff) <= shot.tolerance ? "swish" : diff < 0 ? "short" : "long";
    s.shotPower = s.power;
    s.flightT = 0;
    s.mode = "fly";
    setView({ ...s });
  };

  const shot = shots[view.shotIdx % shots.length];
  const ball = ballPos(view, shot);
  const sweetLeft = Math.max(0, shot.targetPower - shot.tolerance) * 100;
  const sweetWidth = Math.min(100 - sweetLeft, shot.tolerance * 2 * 100);

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        shoot();
      }}
      disabled={!active}
      aria-label="Shoot basketball"
      className="absolute inset-0 flex flex-col justify-between p-3 gap-2 cursor-pointer disabled:cursor-default"
    >
      <div className="relative flex-1 min-h-0 w-full flex items-center justify-center">
        <svg viewBox="0 0 240 140" className="w-full h-full max-h-full">
          <line x1="8" y1="120" x2="232" y2="120" stroke="#FFFFFF" strokeOpacity="0.2" strokeWidth="2" />
          <line x1={shot.hoopX + 18} y1="30" x2={shot.hoopX + 18} y2="120" stroke="#FFFFFF" strokeOpacity="0.3" strokeWidth="4" />
          <rect x={shot.hoopX + 13} y="28" width="8" height="34" rx="2" fill="#FFFFFF" />
          <path d={`M${shot.hoopX - 11} 58 L${shot.hoopX - 7} 76 H${shot.hoopX + 7} L${shot.hoopX + 11} 58`} stroke="#00F2FF" strokeWidth="2" fill="none" />
          <line x1={shot.hoopX - 13} y1="58" x2={shot.hoopX + 13} y2="58" stroke="#FF0080" strokeWidth="4.5" strokeLinecap="round" />
          <circle cx="28" cy="112" r="7" fill={player.color} fillOpacity="0.35" stroke={player.color} strokeWidth="2" />
          <circle cx={ball.x} cy={ball.y} r="8" fill="#FFD700" stroke="#0F0C29" strokeWidth="2" />
          <path d={`M${ball.x - 6} ${ball.y} H${ball.x + 6}`} stroke="#0F0C29" strokeWidth="1.5" />
        </svg>

        {view.mode === "land" && view.result && (
          <div className={`absolute top-2 px-3 py-1 rounded-full text-sm font-black italic uppercase shadow-lg ${view.result === "swish" ? "bg-brand-green text-brand-bg" : "bg-brand-accent text-white"}`}>
            {view.result === "swish" ? "SWISH! +20" : view.result === "short" ? "SHORT!" : "LONG!"}
          </div>
        )}
      </div>

      <div className="w-full max-w-[230px] mx-auto shrink-0">
        <div className="relative h-5 rounded-full bg-white/10 border-2 border-white/20 overflow-hidden">
          <div className="absolute inset-y-0 bg-brand-green/55 border-x-2 border-brand-green" style={{ left: `${sweetLeft}%`, width: `${sweetWidth}%` }} />
          <div className="absolute top-0 bottom-0 w-2 -ml-1 rounded-full bg-white shadow-[0_0_10px_#fff]" style={{ left: `${view.power * 100}%` }} />
        </div>
      </div>
    </button>
  );
}

export default function HoopGame(props: GameProps) {
  const round = useRound(props, { gameId: "hoop", seconds: 25 });
  const shots = useMemo(() => makeShots(round.random(), 40), [round.random]);

  return (
    <GameScreen round={round} players={props.players} title="HOOP!" howTo="Tap when the power hits the sweet spot" detail="+20 swish · basket moves & speeds up">
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} shots={shots} />}
      </PlayerPanels>
    </GameScreen>
  );
}
