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

// HOP! — auto-runner over scrolling blocks of two heights. Tap to hop; clear
// blocks for +1, or collide for −3 and a 1 s stun.

import { useEffect, useMemo, useRef, useState } from "react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useFrame, useRound, type GameProps, type Round } from "../kit/round";

export const sticker = (
  <>
    <rect x="8" y="90" width="104" height="16" rx="7" fill="#4ECCA3" />
    <rect x="74" y="60" width="24" height="32" rx="6" fill="#FF0080" />
    <path d="M22 86 Q 58 14 98 48" fill="none" stroke="#FFD700" strokeWidth="6" strokeLinecap="round" strokeDasharray="9 8" />
    <rect x="20" y="34" width="28" height="28" rx="7" fill="#00F2FF" transform="rotate(-14 34 48)" />
    <circle cx="39" cy="43" r="4" fill="#0F0C29" stroke="none" />
  </>
);

interface ObstacleSpec {
  id: number;
  distance: number;
  tall: boolean;
}

interface Snapshot {
  scroll: number;
  y: number;
  vy: number;
  stunned: boolean;
  flash: { text: string; ok: boolean } | null;
}

const GROUND_PCT = 16;
const RUNNER_X = 16;
const RUNNER_W = 8.5;
const RUNNER_H = 13;
const OBS_W = 6.5;
const GRAVITY = 540;
const JUMP_VY = 188;

function makeTrack(rand: () => number, count: number): ObstacleSpec[] {
  const out: ObstacleSpec[] = [];
  let dist = 92;
  for (let i = 0; i < count; i++) {
    const vEst = Math.min(76, 42 + i * 0.9);
    dist += vEst * (0.95 + rand() * 0.65);
    out.push({ id: i, distance: dist, tall: rand() < 0.42 });
  }
  return out;
}

function Board({ player, round, track }: { player: Player; round: Round; track: ObstacleSpec[] }) {
  const active = round.canPlay(player.id);
  const sim = useRef({
    scroll: 0,
    runTime: 0,
    y: 0,
    vy: 0,
    stunLeft: 0,
    jumpBuffer: 0,
    handled: new Set<number>(),
    flashTimer: 0,
    flash: null as { text: string; ok: boolean } | null,
  });
  const [snap, setSnap] = useState<Snapshot>({ scroll: 0, y: 0, vy: 0, stunned: false, flash: null });

  useEffect(() => {
    sim.current.handled.clear();
  }, [track]);

  useFrame(active, (dt) => {
    const s = sim.current;
    if (s.flashTimer > 0) {
      s.flashTimer = Math.max(0, s.flashTimer - dt);
      if (s.flashTimer === 0) s.flash = null;
    }

    if (s.stunLeft > 0) {
      s.stunLeft = Math.max(0, s.stunLeft - dt);
      s.jumpBuffer = 0;
    } else {
      s.runTime += dt;
      s.scroll += Math.min(76, 42 + s.runTime * 1.15) * dt;
    }

    if (s.jumpBuffer > 0) s.jumpBuffer = Math.max(0, s.jumpBuffer - dt);
    if (s.jumpBuffer > 0 && s.y <= 0 && s.stunLeft <= 0) {
      s.vy = JUMP_VY;
      s.jumpBuffer = 0;
    }

    if (s.y > 0 || s.vy > 0) {
      s.y += s.vy * dt;
      s.vy -= GRAVITY * dt;
      if (s.y <= 0) {
        s.y = 0;
        s.vy = 0;
      }
    }

    if (s.stunLeft <= 0) {
      for (const obs of track) {
        if (s.handled.has(obs.id)) continue;
        const obsX = obs.distance - s.scroll;
        if (obsX > 115) break;
        const obsH = obs.tall ? 22 : 13;
        const hitX = RUNNER_X + RUNNER_W - 1.2 > obsX + 0.8 && RUNNER_X + 1.2 < obsX + OBS_W - 0.8;
        if (hitX && s.y < obsH - 1.2) {
          s.handled.add(obs.id);
          s.stunLeft = 1.0;
          s.flash = { text: "BONK! −3", ok: false };
          s.flashTimer = 0.75;
          round.addScore(player.id, -3);
          break;
        }
        if (obsX + OBS_W < RUNNER_X) {
          s.handled.add(obs.id);
          s.flash = { text: "+1", ok: true };
          s.flashTimer = 0.4;
          round.addScore(player.id, 1);
        }
      }
    }

    setSnap({ scroll: s.scroll, y: s.y, vy: s.vy, stunned: s.stunLeft > 0, flash: s.flash });
  });

  const tapJump = () => {
    const s = sim.current;
    if (!active || s.stunLeft > 0) return;
    if (s.y <= 0) {
      s.vy = JUMP_VY;
      s.jumpBuffer = 0;
    } else {
      s.jumpBuffer = 0.13;
    }
  };

  const visible = track.filter((obs) => {
    const x = obs.distance - snap.scroll;
    return x > -15 && x < 115;
  });
  const tilt = snap.stunned ? -16 : snap.y > 0 ? Math.max(-18, Math.min(18, -snap.vy * 0.09)) : 0;

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        tapJump();
      }}
      className={`absolute inset-0 cursor-pointer overflow-hidden transition-colors ${snap.stunned ? "bg-[#FF4D4D]/15" : ""}`}
      aria-label="Hop"
    >
      <div className="absolute inset-x-0 bottom-0 border-t-2 border-brand-green/60 bg-brand-bg/90" style={{ height: `${GROUND_PCT}%` }}>
        <div
          className="h-1.5 opacity-50"
          style={{
            backgroundImage: "repeating-linear-gradient(90deg, #4ECCA3 0 18px, transparent 18px 36px)",
            backgroundPositionX: `${-(snap.scroll * 4) % 36}px`,
          }}
        />
      </div>

      {visible.map((obs) => (
        <div
          key={obs.id}
          className="absolute rounded-md border-2 border-brand-bg"
          style={{
            left: `${obs.distance - snap.scroll}%`,
            width: `${OBS_W}%`,
            bottom: `${GROUND_PCT}%`,
            height: `${obs.tall ? 22 : 13}%`,
            backgroundColor: obs.tall ? "#FFD700" : "#FF0080",
            boxShadow: obs.tall ? "0 0 12px rgba(255,215,0,0.45)" : "0 0 12px rgba(255,0,128,0.45)",
          }}
        />
      ))}

      <div
        className={`absolute rounded-lg border-2 border-white flex items-center justify-end pr-1 ${snap.stunned ? "animate-pulse" : ""}`}
        style={{
          left: `${RUNNER_X}%`,
          width: `${RUNNER_W}%`,
          bottom: `${GROUND_PCT + snap.y}%`,
          height: `${RUNNER_H}%`,
          backgroundColor: snap.stunned ? "#FF4D4D" : player.color,
          boxShadow: `0 0 16px ${snap.stunned ? "#FF4D4D" : player.color}`,
          transform: `rotate(${tilt}deg)`,
        }}
      >
        <span className="w-1.5 h-1.5 rounded-full bg-brand-bg" />
      </div>

      {snap.flash && (
        <div className={`absolute top-3 right-3 text-lg sm:text-xl font-black italic uppercase drop-shadow ${snap.flash.ok ? "text-brand-green" : "text-[#FF4D4D]"}`}>
          {snap.flash.text}
        </div>
      )}
    </button>
  );
}

export default function JumpGame(props: GameProps) {
  const round = useRound(props, { gameId: "jump", seconds: 30 });
  const track = useMemo(() => makeTrack(round.random(), 120), [round.random]);

  return (
    <GameScreen round={round} players={props.players} title="HOP!" howTo="Tap to jump over blocks" detail="+1 cleared · −3 & 1s stun on hit">
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} track={track} />}
      </PlayerPanels>
    </GameScreen>
  );
}
