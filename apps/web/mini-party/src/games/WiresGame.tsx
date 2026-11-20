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

// DEFUSE! — cut the bomb's coloured wires in the exact order shown. Defusing
// awards +25 and adds longer sequences; one wrong cut triggers BOOM (−10).

import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import { GameScreen, PlayerPanels, useRound, type GameProps, type Round } from "../kit/round";
import { randInt, shuffle } from "../kit/logic";

export const sticker = (
  <>
    <rect x="16" y="18" width="88" height="84" rx="16" fill="#4D79FF" />
    <rect x="26" y="28" width="68" height="64" rx="10" fill="#16213E" />
    <path d="M26 42 H94" stroke="#FF4D4D" strokeWidth="8" strokeLinecap="round" />
    <path d="M26 60 H48 M72 60 H94" stroke="#FFD93D" strokeWidth="8" strokeLinecap="round" />
    <path d="M26 78 H94" stroke="#00F2FF" strokeWidth="8" strokeLinecap="round" />
    <polygon points="60,44 65,55 76,55 67,62 71,74 60,67 49,74 53,62 44,55 55,55" fill="#FFD700" />
  </>
);

interface WireColor {
  name: string;
  hex: string;
}

const WIRE_COLORS: readonly WireColor[] = [
  { name: "RED", hex: "#FF4D4D" },
  { name: "BLUE", hex: "#4D79FF" },
  { name: "YELLOW", hex: "#FFD93D" },
  { name: "GREEN", hex: "#4ECCA3" },
  { name: "PINK", hex: "#FF0080" },
  { name: "CYAN", hex: "#00F2FF" },
];

interface BombSeed {
  baseCount: number;
  palette: WireColor[];
  orderIdx: number[];
  curves: number[];
}

function makeBombs(rand: () => number, count: number): BombSeed[] {
  return Array.from({ length: count }, () => ({
    baseCount: randInt(rand, 4, 6),
    palette: shuffle(rand, WIRE_COLORS),
    orderIdx: shuffle(rand, [0, 1, 2, 3, 4, 5]),
    curves: Array.from({ length: 6 }, () => randInt(rand, -7, 7)),
  }));
}

function Board({ player, round, bombs }: { player: Player; round: Round; bombs: BombSeed[] }) {
  const [bombIdx, setBombIdx] = useState(0);
  const [defused, setDefused] = useState(0);
  const [cutNames, setCutNames] = useState<string[]>([]);
  const [status, setStatus] = useState<"idle" | "defused" | "boom">("idle");
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const bomb = bombs[bombIdx % bombs.length];
  const orderLen = Math.min(5, 3 + defused);
  const wireCount = Math.max(bomb.baseCount, orderLen);
  const wires = bomb.palette.slice(0, wireCount);
  const order = bomb.orderIdx.filter((i) => i < wireCount).slice(0, orderLen).map((i) => wires[i].name);
  const canTap = round.canPlay(player.id) && status === "idle";

  const cutWire = (name: string) => {
    if (!canTap || cutNames.includes(name)) return;
    if (name === order[cutNames.length]) {
      const nextCut = [...cutNames, name];
      setCutNames(nextCut);
      if (nextCut.length === order.length) {
        round.addScore(player.id, 25);
        setStatus("defused");
        timerRef.current = window.setTimeout(() => {
          setBombIdx((i) => i + 1);
          setDefused((d) => d + 1);
          setCutNames([]);
          setStatus("idle");
        }, 380);
      }
      return;
    }

    round.addScore(player.id, -10);
    setStatus("boom");
    timerRef.current = window.setTimeout(() => {
      setBombIdx((i) => i + 1);
      setCutNames([]);
      setStatus("idle");
    }, 480);
  };

  return (
    <motion.div
      animate={status === "boom" ? { x: [-5, 5, -4, 4, 0] } : { x: 0 }}
      transition={{ duration: 0.25 }}
      className="h-full flex flex-col justify-between gap-2 p-2.5 sm:p-3 min-h-0"
    >
      <div className="px-2.5 py-1.5 rounded-xl bg-brand-bg/90 border border-white/10 text-center shrink-0">
        <span className="text-[10px] sm:text-xs font-black uppercase tracking-widest text-white/50 mr-1.5">
          CUT:
        </span>
        {order.map((name, i) => {
          const isCut = i < cutNames.length;
          const colorHex = wires.find((w) => w.name === name)?.hex ?? "#FFFFFF";
          return (
            <Fragment key={`${name}-${i}`}>
              {i > 0 && <span className="text-white/40 mx-1 text-xs">→</span>}
              <span
                className={`text-xs sm:text-sm font-black italic uppercase tracking-wide ${isCut ? "line-through opacity-30" : ""}`}
                style={{ color: isCut ? "#FFFFFF" : colorHex }}
              >
                {name}
              </span>
            </Fragment>
          );
        })}
      </div>

      <div className="relative flex-1 min-h-0 rounded-2xl bg-brand-bg/85 border-2 border-white/10 px-2 py-1.5 flex flex-col justify-evenly">
        {wires.map((w, i) => {
          const isCut = cutNames.includes(w.name);
          const sag = 15 + bomb.curves[i];
          return (
            <button
              key={`${bombIdx}-${w.name}`}
              type="button"
              onPointerDown={(e) => {
                e.preventDefault();
                cutWire(w.name);
              }}
              disabled={!canTap || isCut}
              className="w-full flex items-center gap-2 px-1 py-0.5 rounded-lg hover:bg-white/5 active:scale-[0.98] transition-transform touch-none cursor-pointer disabled:cursor-default"
              aria-label={`Cut ${w.name} wire`}
            >
              <span
                className={`w-14 text-left text-[10px] sm:text-xs font-black uppercase tracking-wider shrink-0 ${isCut ? "opacity-30 line-through" : ""}`}
                style={{ color: w.hex }}
              >
                {w.name}
              </span>
              <svg viewBox="0 0 200 30" className="flex-1 h-5 sm:h-6 overflow-visible">
                <rect x="0" y="7" width="12" height="16" rx="3" fill="#475569" />
                <rect x="188" y="7" width="12" height="16" rx="3" fill="#475569" />
                {isCut ? (
                  <>
                    <motion.path
                      initial={{ d: `M 12 15 Q 55 ${sag} 98 15` }}
                      animate={{ d: `M 12 15 Q 48 ${sag - 6} 78 6` }}
                      transition={{ duration: 0.16 }}
                      stroke={w.hex}
                      strokeWidth="7"
                      strokeLinecap="round"
                      fill="none"
                      opacity="0.55"
                    />
                    <motion.path
                      initial={{ d: `M 102 15 Q 145 ${sag} 188 15` }}
                      animate={{ d: `M 122 24 Q 152 ${sag + 6} 188 15` }}
                      transition={{ duration: 0.16 }}
                      stroke={w.hex}
                      strokeWidth="7"
                      strokeLinecap="round"
                      fill="none"
                      opacity="0.55"
                    />
                    <circle cx="100" cy="15" r="5" fill="#FFD700" />
                  </>
                ) : (
                  <path d={`M 12 15 Q 100 ${sag} 188 15`} stroke={w.hex} strokeWidth="7" strokeLinecap="round" fill="none" />
                )}
              </svg>
            </button>
          );
        })}

        {status !== "idle" && (
          <motion.div
            initial={{ opacity: 0, scale: 0.85 }}
            animate={{ opacity: 1, scale: 1 }}
            className={`absolute inset-0 rounded-2xl flex items-center justify-center backdrop-blur-[2px] ${
              status === "boom" ? "bg-[#FF4D4D]/45" : "bg-brand-green/35"
            }`}
          >
            <span className="text-3xl sm:text-4xl font-black italic uppercase drop-shadow">
              {status === "boom" ? "BOOM! −10" : "DEFUSED! +25"}
            </span>
          </motion.div>
        )}
      </div>
    </motion.div>
  );
}

export default function WiresGame(props: GameProps) {
  const round = useRound(props, { gameId: "wires", seconds: 30 });
  const bombs = useMemo(() => makeBombs(round.random(), 40), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="DEFUSE!"
      howTo="Cut the wires in order"
      detail="+25 defuse (longer each time) · wrong wire = BOOM −10"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} bombs={bombs} />}
      </PlayerPanels>
    </GameScreen>
  );
}
