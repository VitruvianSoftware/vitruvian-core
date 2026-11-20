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

// BEAT! — notes slide down a lane toward the hit line on a seeded musical
// beat. Tap as each note crosses: PERFECT ±60ms (+10), GOOD ±140ms (+5), bad tap −2.

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
    <rect x="10" y="84" width="100" height="14" rx="7" fill="#00F2FF" />
    <ellipse
      cx="46"
      cy="62"
      rx="18"
      ry="13"
      fill="#FF0080"
      transform="rotate(-18 46 62)"
    />
    <path
      d="M60 58 V20 L86 30 V44 L60 34"
      fill="#FFD700"
      strokeLinejoin="round"
    />
    <path
      d="M22 76 l-8 -10 M98 76 l8 -10 M60 104 v8"
      stroke="#4ECCA3"
      strokeWidth="6"
      strokeLinecap="round"
      fill="none"
    />
  </>
);

interface NoteSpec {
  id: number;
  timeMs: number;
  offbeat: boolean;
}

type NoteStatus = "pending" | "hit" | "miss";

const BEAT_MS = 560;
const TRAVEL_MS = 1350;
const HIT_Y = 82;
const PERFECT_MS = 60;
const GOOD_MS = 140;

function makeChart(rand: () => number): NoteSpec[] {
  const notes: NoteSpec[] = [];
  let id = 0;
  let skippedLast = false;
  for (let t = 1250; t <= 24200; t += BEAT_MS) {
    const progress = (t - 1250) / (24200 - 1250);
    if (skippedLast || rand() < 0.62 + progress * 0.28) {
      notes.push({ id: id++, timeMs: t, offbeat: false });
      skippedLast = false;
    } else {
      skippedLast = true;
    }
    if (t + BEAT_MS / 2 <= 24200 && rand() < 0.08 + progress * 0.36) {
      notes.push({ id: id++, timeMs: t + BEAT_MS / 2, offbeat: true });
    }
  }
  return notes;
}

function Board({
  player,
  round,
  chart,
}: {
  player: Player;
  round: Round;
  chart: NoteSpec[];
}) {
  const active = round.canPlay(player.id);
  const startMsRef = useRef<number | null>(null);
  const statusRef = useRef<NoteStatus[]>(chart.map(() => "pending"));
  const judgeTimerRef = useRef<number | null>(null);
  const pulseTimerRef = useRef<number | null>(null);
  const [nowMs, setNowMs] = useState(0);
  const [judgement, setJudgement] = useState<{
    text: string;
    color: string;
    seq: number;
  } | null>(null);
  const [pulse, setPulse] = useState(false);

  useEffect(() => {
    statusRef.current = chart.map(() => "pending");
  }, [chart]);

  useEffect(() => {
    if (active && startMsRef.current === null)
      startMsRef.current = performance.now();
  }, [active]);

  useEffect(() => {
    return () => {
      if (judgeTimerRef.current !== null)
        window.clearTimeout(judgeTimerRef.current);
      if (pulseTimerRef.current !== null)
        window.clearTimeout(pulseTimerRef.current);
    };
  }, []);

  const showJudge = (text: string, color: string) => {
    if (judgeTimerRef.current !== null)
      window.clearTimeout(judgeTimerRef.current);
    setJudgement((prev) => ({ text, color, seq: (prev?.seq ?? 0) + 1 }));
    judgeTimerRef.current = window.setTimeout(() => setJudgement(null), 450);
  };

  useFrame(active, () => {
    if (startMsRef.current === null) startMsRef.current = performance.now();
    const elapsed = performance.now() - startMsRef.current;
    let missed = false;
    for (let i = 0; i < chart.length; i++) {
      if (statusRef.current[i] !== "pending") continue;
      if (elapsed - chart[i].timeMs > GOOD_MS) {
        statusRef.current[i] = "miss";
        missed = true;
      } else if (chart[i].timeMs > elapsed + GOOD_MS) {
        break;
      }
    }
    if (missed) showJudge("MISS", "#FF4D4D");
    setNowMs(elapsed);
  });

  const tap = () => {
    if (!active || startMsRef.current === null) return;
    const tapMs = performance.now() - startMsRef.current;

    setPulse(true);
    if (pulseTimerRef.current !== null)
      window.clearTimeout(pulseTimerRef.current);
    pulseTimerRef.current = window.setTimeout(() => setPulse(false), 110);

    let bestIdx = -1;
    let bestDiff = Infinity;
    for (let i = 0; i < chart.length; i++) {
      if (statusRef.current[i] !== "pending") continue;
      const diff = Math.abs(chart[i].timeMs - tapMs);
      if (diff <= GOOD_MS && diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }

    if (bestIdx >= 0) {
      statusRef.current[bestIdx] = "hit";
      if (bestDiff <= PERFECT_MS) {
        round.addScore(player.id, 10);
        showJudge("PERFECT +10", "#FFD700");
      } else {
        round.addScore(player.id, 5);
        showJudge("GOOD +5", "#4ECCA3");
      }
    } else {
      round.addScore(player.id, -2);
      showJudge("−2", "#FF4D4D");
    }
  };

  const visible = chart.filter((note, i) => {
    if (statusRef.current[i] !== "pending") return false;
    const until = note.timeMs - nowMs;
    return until <= TRAVEL_MS && until >= -GOOD_MS;
  });

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        tap();
      }}
      className="absolute inset-0 cursor-pointer overflow-hidden flex justify-center"
      aria-label="Hit beat"
    >
      <div className="relative h-full w-full max-w-[176px] border-x-2 border-white/10 bg-brand-bg/70">
        <div
          className={`absolute inset-x-1 h-2.5 -translate-y-1/2 rounded-full transition-all ${
            pulse
              ? "bg-white shadow-[0_0_20px_#00F2FF]"
              : "bg-brand-cyan/65 shadow-[0_0_12px_rgba(0,242,255,0.5)]"
          }`}
          style={{ top: `${HIT_Y}%` }}
        />

        {visible.map((note) => (
          <div
            key={note.id}
            className="absolute left-3 right-3 h-4 -translate-y-1/2 rounded-full border-2 border-white"
            style={{
              top: `${HIT_Y * (1 - (note.timeMs - nowMs) / TRAVEL_MS)}%`,
              backgroundColor: note.offbeat ? "#FFD700" : "#FF0080",
              boxShadow: note.offbeat
                ? "0 0 14px rgba(255,215,0,0.75)"
                : "0 0 14px rgba(255,0,128,0.75)",
            }}
          />
        ))}

        {judgement && (
          <div
            key={judgement.seq}
            className="absolute inset-x-0 text-center text-lg sm:text-xl font-black italic uppercase tracking-tight drop-shadow pointer-events-none"
            style={{ top: `${HIT_Y - 16}%`, color: judgement.color }}
          >
            {judgement.text}
          </div>
        )}
      </div>
    </button>
  );
}

export default function RhythmGame(props: GameProps) {
  const round = useRound(props, { gameId: "rhythm", seconds: 25 });
  const chart = useMemo(() => makeChart(round.random()), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="BEAT!"
      howTo="Tap as notes cross the cyan line"
      detail="PERFECT ±60ms (+10) · GOOD ±140ms (+5) · off-beat −2"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} chart={chart} />}
      </PlayerPanels>
    </GameScreen>
  );
}
