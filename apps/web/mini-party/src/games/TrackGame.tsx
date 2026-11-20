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

// TRACK! — watch which of the 5 balls flashes gold, follow it as all 5
// weave and bounce around the arena, then tap it when they stop.

import { useMemo, useRef, useState } from "react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useFrame, useRound, type GameProps, type Round } from "../kit/round";
import { randInt, shuffle } from "../kit/logic";

export const sticker = (
  <>
    <path d="M20 82 Q 44 28 74 56" stroke="#FFFFFF" strokeWidth="6" strokeDasharray="6 7" strokeLinecap="round" fill="none" />
    <path d="M28 24 Q 58 76 92 78" stroke="#FF0080" strokeWidth="6" strokeDasharray="6 7" strokeLinecap="round" fill="none" />
    <circle cx="24" cy="30" r="13" fill="#00F2FF" />
    <circle cx="94" cy="30" r="13" fill="#00F2FF" />
    <circle cx="26" cy="88" r="13" fill="#00F2FF" />
    <circle cx="94" cy="86" r="13" fill="#00F2FF" />
    <circle cx="60" cy="58" r="17" fill="#FFD700" />
  </>
);

interface Point {
  x: number;
  y: number;
}
interface TrackRound {
  target: number;
  frames: Point[][];
}

const BALL_COUNT = 5;
const TOTAL_ROUNDS = 4;
const ARENA_W = 120;
const ARENA_H = 100;
const BALL_R = 8.5;
const MARGIN = 11;
const MOVE_STEPS = 180;
const MOVE_SEC = 3.0;
const SHOW_SEC = 1.0;
const REVEAL_SEC = 0.95;
const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

function makeRounds(rand: () => number): TrackRound[] {
  return Array.from({ length: TOTAL_ROUNDS }, (_, roundIdx) => {
    const slots = shuffle(
      rand,
      Array.from({ length: BALL_COUNT }, (__, k) => {
        const a = (k * Math.PI * 2) / BALL_COUNT - Math.PI / 2;
        return {
          x: ARENA_W / 2 + Math.cos(a) * 28 + (rand() - 0.5) * 8,
          y: ARENA_H / 2 + Math.sin(a) * 24 + (rand() - 0.5) * 6,
        };
      }),
    );
    const speed = 52 + roundIdx * 18;
    const state = slots.map((p) => ({
      ...p,
      theta: rand() * Math.PI * 2,
      freq: 1.5 + rand() * 1.5,
      phase: rand() * Math.PI * 2,
    }));

    const frames: Point[][] = [state.map((b) => ({ x: b.x, y: b.y }))];
    const dt = MOVE_SEC / MOVE_STEPS;
    const minDist = BALL_R * 2.15;

    for (let s = 0; s < MOVE_STEPS; s++) {
      const t = s * dt;
      for (const b of state) {
        b.theta += Math.sin(t * b.freq + b.phase) * 1.4 * dt;
        let vx = Math.cos(b.theta) * speed;
        let vy = Math.sin(b.theta) * speed;
        b.x += vx * dt;
        b.y += vy * dt;
        if (b.x < MARGIN || b.x > ARENA_W - MARGIN) {
          b.x = clamp(b.x, MARGIN, ARENA_W - MARGIN);
          vx = -vx;
          b.theta = Math.atan2(vy, vx);
        }
        if (b.y < MARGIN || b.y > ARENA_H - MARGIN) {
          b.y = clamp(b.y, MARGIN, ARENA_H - MARGIN);
          vy = -vy;
          b.theta = Math.atan2(vy, vx);
        }
      }
      for (let i = 0; i < BALL_COUNT; i++) {
        for (let j = i + 1; j < BALL_COUNT; j++) {
          const dx = state[j].x - state[i].x;
          const dy = state[j].y - state[i].y;
          const dist = Math.hypot(dx, dy) || 0.01;
          if (dist < minDist) {
            const push = ((minDist - dist) * 0.5) / dist;
            state[i].x = clamp(state[i].x - dx * push, MARGIN, ARENA_W - MARGIN);
            state[i].y = clamp(state[i].y - dy * push, MARGIN, ARENA_H - MARGIN);
            state[j].x = clamp(state[j].x + dx * push, MARGIN, ARENA_W - MARGIN);
            state[j].y = clamp(state[j].y + dy * push, MARGIN, ARENA_H - MARGIN);
          }
        }
      }
      frames.push(state.map((b) => ({ x: b.x, y: b.y })));
    }
    return { target: randInt(rand, 0, BALL_COUNT - 1), frames };
  });
}

function Board({ player, round, rounds }: { player: Player; round: Round; rounds: TrackRound[] }) {
  const [roundIdx, setRoundIdx] = useState(0);
  const [stage, setStage] = useState<"show" | "move" | "pick" | "reveal">("show");
  const [stageTime, setStageTime] = useState(0);
  const [picked, setPicked] = useState<number | null>(null);
  const elapsedRef = useRef(0);

  const cur = rounds[Math.min(roundIdx, rounds.length - 1)];
  const active = round.canPlay(player.id);

  useFrame(active && stage !== "pick", (dt) => {
    elapsedRef.current += dt;
    const t = elapsedRef.current;
    if (stage === "show") {
      if (t >= SHOW_SEC) {
        elapsedRef.current = 0;
        setStageTime(0);
        setStage("move");
      } else setStageTime(t);
    } else if (stage === "move") {
      if (t >= MOVE_SEC) {
        elapsedRef.current = 0;
        setStageTime(MOVE_SEC);
        setStage("pick");
      } else setStageTime(t);
    } else if (stage === "reveal" && t >= REVEAL_SEC) {
      elapsedRef.current = 0;
      setStageTime(0);
      if (roundIdx + 1 >= TOTAL_ROUNDS) round.finish(player.id);
      else {
        setRoundIdx((i) => i + 1);
        setPicked(null);
        setStage("show");
      }
    }
  });

  const positions: Point[] = (() => {
    if (stage === "show") return cur.frames[0];
    if (stage === "pick" || stage === "reveal") return cur.frames[MOVE_STEPS];
    const u = Math.min(MOVE_STEPS, (stageTime / MOVE_SEC) * MOVE_STEPS);
    const i0 = Math.floor(u);
    const i1 = Math.min(MOVE_STEPS, i0 + 1);
    const frac = u - i0;
    return cur.frames[i0].map((p0, k) => ({
      x: p0.x + (cur.frames[i1][k].x - p0.x) * frac,
      y: p0.y + (cur.frames[i1][k].y - p0.y) * frac,
    }));
  })();

  const tapBall = (idx: number) => {
    if (!active || stage !== "pick") return;
    setPicked(idx);
    if (idx === cur.target) round.addScore(player.id, 30);
    elapsedRef.current = 0;
    setStageTime(0);
    setStage("reveal");
  };

  const prompt =
    stage === "show"
      ? "WATCH GOLD!"
      : stage === "move"
        ? "TRACK IT!"
        : stage === "pick"
          ? "TAP IT!"
          : picked === cur.target
            ? "FOUND! +30"
            : "MISSED!";
  const promptTone =
    stage === "reveal"
      ? picked === cur.target
        ? "text-brand-green"
        : "text-[#FF4D4D]"
      : stage === "pick"
        ? "text-brand-gold"
        : "text-brand-cyan";

  return (
    <div className="h-full flex flex-col gap-2 p-2.5 sm:p-3 min-h-0">
      <div className="flex items-center justify-between px-1 shrink-0">
        <span className="text-[10px] sm:text-xs font-black uppercase tracking-widest text-white/50">
          ROUND {roundIdx + 1}/{TOTAL_ROUNDS}
        </span>
        <span className={`text-xs sm:text-sm font-black italic uppercase ${promptTone}`}>{prompt}</span>
      </div>
      <div className="relative flex-1 min-h-0 rounded-2xl bg-brand-bg/90 border-2 border-white/10 overflow-hidden">
        <svg viewBox={`0 0 ${ARENA_W} ${ARENA_H}`} className="w-full h-full touch-none">
          {positions.map((pos, idx) => {
            const isGold = (stage === "show" || stage === "reveal") && idx === cur.target;
            const isWrong = stage === "reveal" && picked === idx && idx !== cur.target;
            const fill = isGold ? "#FFD700" : isWrong ? "#FF4D4D" : "#00F2FF";
            return (
              <g
                key={idx}
                onPointerDown={(e) => {
                  e.preventDefault();
                  tapBall(idx);
                }}
                className={stage === "pick" && active ? "cursor-pointer touch-none" : "touch-none"}
              >
                <circle cx={pos.x} cy={pos.y} r={13} fill="transparent" />
                {isGold && (
                  <circle
                    cx={pos.x}
                    cy={pos.y}
                    r={BALL_R + 3}
                    fill="none"
                    stroke={stage === "reveal" && picked === cur.target ? "#4ECCA3" : "#FFD700"}
                    strokeWidth="2"
                    opacity="0.85"
                  />
                )}
                <circle cx={pos.x} cy={pos.y} r={BALL_R} fill={fill} stroke="#0F0C29" strokeWidth="2" />
                <circle cx={pos.x - 2.5} cy={pos.y - 2.5} r={2.4} fill="#FFFFFF" opacity="0.6" />
              </g>
            );
          })}
        </svg>
      </div>
    </div>
  );
}

export default function TrackGame(props: GameProps) {
  const round = useRound(props, { gameId: "track", seconds: 32 });
  const rounds = useMemo(() => makeRounds(round.random()), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="TRACK!"
      howTo="Track the gold ball and tap it when they stop"
      detail="4 rounds · +30 right · 0 wrong"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} rounds={rounds} />}
      </PlayerPanels>
    </GameScreen>
  );
}
