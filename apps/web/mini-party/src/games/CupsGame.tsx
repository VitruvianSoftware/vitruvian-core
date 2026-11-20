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

// CUPS! — watch where the ball hides, track the animated cup swaps, and tap
// the right cup across four faster rounds.

import { useEffect, useMemo, useRef, useState, type PointerEvent } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useRound, type GameProps, type Round } from "../kit/round";
import { randInt } from "../kit/logic";

export const sticker = (
  <>
    <path d="M12 96 L18 50 H44 L50 96 Z" fill="#FF0080" />
    <circle cx="60" cy="90" r="12" fill="#FFD700" />
    <path d="M41 64 L47 18 H73 L79 64 Z" fill="#00F2FF" />
    <path d="M70 96 L76 50 H102 L108 96 Z" fill="#FF0080" />
  </>
);

interface CupRound {
  ballCup: number;
  swaps: [number, number][];
  swapMs: number;
}

const TOTAL_ROUNDS = 4;
// Every cup looks the same: the only way to win is to follow the shuffle.
const CUP_COLOR = "#FF0080";

function makeRounds(rand: () => number): CupRound[] {
  const speeds = [400, 320, 260, 210];
  return Array.from({ length: TOTAL_ROUNDS }, (_, r) => {
    const ballCup = randInt(rand, 0, 2);
    const swaps: [number, number][] = [];
    let prevKey = "";
    for (let i = 0; i < 5 + r * 2; i++) {
      let a = randInt(rand, 0, 2);
      let b = (a + randInt(rand, 1, 2)) % 3;
      if (a > b) [a, b] = [b, a];
      if (`${a}-${b}` === prevKey) {
        a = (a + 1) % 3;
        b = (a + 1) % 3;
        if (a > b) [a, b] = [b, a];
      }
      prevKey = `${a}-${b}`;
      swaps.push([a, b]);
    }
    return { ballCup, swaps, swapMs: speeds[r] };
  });
}

type Step = "wait" | "show" | "shuffle" | "pick" | "reveal";

function Board({ player, round, rounds }: { player: Player; round: Round; rounds: CupRound[] }) {
  const [roundIdx, setRoundIdx] = useState(0);
  const [step, setStep] = useState<Step>("wait");
  const [showLifted, setShowLifted] = useState(false);
  const [slots, setSlots] = useState<[number, number, number]>([0, 1, 2]);
  const [swapPair, setSwapPair] = useState<[number, number] | null>(null);
  const [pickedCup, setPickedCup] = useState<number | null>(null);
  const timersRef = useRef<number[]>([]);

  const clearTimers = () => {
    timersRef.current.forEach((id) => window.clearTimeout(id));
    timersRef.current = [];
  };

  useEffect(() => clearTimers, []);
  useEffect(() => {
    if (round.phase === "playing" && step === "wait") setStep("show");
  }, [round.phase, step]);

  const cur = rounds[roundIdx];

  useEffect(() => {
    if (round.phase !== "playing" || round.finished[player.id]) {
      clearTimers();
      return;
    }
    if (step === "show") {
      clearTimers();
      setShowLifted(true);
      timersRef.current.push(
        window.setTimeout(() => setShowLifted(false), 720),
        window.setTimeout(() => setStep("shuffle"), 960),
      );
      return clearTimers;
    }
    if (step === "shuffle") {
      clearTimers();
      let live: [number, number, number] = [0, 1, 2];
      cur.swaps.forEach(([slotA, slotB], i) => {
        timersRef.current.push(
          window.setTimeout(() => {
            const cupA = live.indexOf(slotA);
            const cupB = live.indexOf(slotB);
            const next: [number, number, number] = [...live];
            next[cupA] = slotB;
            next[cupB] = slotA;
            live = next;
            setSlots(next);
            setSwapPair([cupA, cupB]);
          }, 50 + i * cur.swapMs),
        );
      });
      timersRef.current.push(
        window.setTimeout(() => {
          setSwapPair(null);
          setStep("pick");
        }, 50 + cur.swaps.length * cur.swapMs),
      );
      return clearTimers;
    }
  }, [step, roundIdx, round.phase, round.finished, player.id, cur]);

  const choose = (cupId: number) => {
    if (!round.canPlay(player.id) || step !== "pick") return;
    if (cupId === cur.ballCup) round.addScore(player.id, 30);
    setPickedCup(cupId);
    setStep("reveal");
    clearTimers();
    timersRef.current.push(
      window.setTimeout(() => {
        if (roundIdx + 1 >= TOTAL_ROUNDS) {
          round.finish(player.id);
          return;
        }
        setRoundIdx((i) => i + 1);
        setSlots([0, 1, 2]);
        setPickedCup(null);
        setSwapPair(null);
        setStep("show");
      }, 880),
    );
  };

  const rightPick = pickedCup === cur.ballCup;
  const status =
    step === "show" ? "Watch!" : step === "shuffle" ? "Track it..." : step === "pick" ? "Tap a cup!" : rightPick ? "+30!" : "Empty!";

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-3 min-h-0">
      <div className="flex items-center justify-between w-full max-w-[240px] shrink-0">
        <div className="flex gap-1.5">
          {rounds.map((_, i) => (
            <span key={i} className={`h-2 w-6 rounded-full ${i < roundIdx ? "bg-brand-green" : i === roundIdx ? "bg-brand-cyan" : "bg-white/15"}`} />
          ))}
        </div>
        <span className="text-[10px] font-black uppercase tracking-widest text-white/50">{roundIdx + 1} / {TOTAL_ROUNDS}</span>
      </div>

      <div className={`text-xl sm:text-2xl font-black italic uppercase shrink-0 ${step === "reveal" ? (rightPick ? "text-brand-green" : "text-brand-accent") : step === "pick" ? "text-brand-gold animate-pulse" : "text-white"}`}>
        {status}
      </div>

      <div className="relative flex-1 min-h-0 w-full max-w-[250px] flex items-end pb-3">
        <div className="relative w-full h-32 sm:h-40">
          {(step === "show" || step === "reveal") && (
            <motion.div className="absolute bottom-2 left-0 w-1/3 flex justify-center pointer-events-none z-0" animate={{ x: `${slots[cur.ballCup] * 100}%` }} transition={{ duration: 0 }}>
              <div className="w-7 h-7 sm:w-8 sm:h-8 rounded-full bg-brand-gold border-2 border-white shadow-[0_0_16px_rgba(255,215,0,0.85)]" />
            </motion.div>
          )}
          {[0, 1, 2].map((cupId) => {
            const lifted = (step === "show" && showLifted && cupId === cur.ballCup) || (step === "reveal" && (cupId === pickedCup || cupId === cur.ballCup));
            const zIndex = swapPair?.[0] === cupId ? 20 : swapPair?.[1] === cupId ? 10 : 5;
            return (
              <motion.button
                key={cupId}
                type="button"
                onPointerDown={(e: PointerEvent<HTMLButtonElement>) => {
                  e.preventDefault();
                  choose(cupId);
                }}
                disabled={step !== "pick" || !round.canPlay(player.id)}
                animate={{ x: `${slots[cupId] * 100}%` }}
                transition={{ duration: Math.max(0.14, (cur.swapMs / 1000) * 0.8), ease: "easeInOut" }}
                style={{ zIndex }}
                aria-label={`Cup ${cupId + 1}`}
                className="absolute inset-y-0 left-0 w-1/3 flex items-end justify-center cursor-pointer disabled:cursor-default"
              >
                <motion.div animate={{ y: lifted ? -36 : 0 }} transition={{ type: "spring", stiffness: 360, damping: 24 }} className="w-16 h-20 sm:w-20 sm:h-24">
                  <svg viewBox="0 0 80 96" className="w-full h-full drop-shadow-[0_6px_12px_rgba(0,0,0,0.5)]">
                    <path d="M14 14 H66 L74 88 H6 Z" fill={CUP_COLOR} stroke="#FFFFFF" strokeWidth="4" strokeLinejoin="round" />
                    <rect x="4" y="82" width="72" height="10" rx="5" fill="#0F0C29" stroke="#FFFFFF" strokeWidth="3" />
                  </svg>
                </motion.div>
              </motion.button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default function CupsGame(props: GameProps) {
  const round = useRound(props, { gameId: "cups", seconds: 35 });
  const rounds = useMemo(() => makeRounds(round.random()), [round.random]);

  return (
    <GameScreen round={round} players={props.players} title="CUPS!" howTo="Follow the ball under the cup" detail="4 rounds · +30 each right pick">
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} rounds={rounds} />}
      </PlayerPanels>
    </GameScreen>
  );
}
