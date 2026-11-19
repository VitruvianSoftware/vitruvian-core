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

import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Player } from "../types";
import { Scale } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function BalanceGame({ players, onEnd, myPlayerId }: GameProps) {
  const [ballPositions, setBallPositions] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 50])),
  );
  const [isStarted, setIsStarted] = useState(false);
  const [survivals, setSurvivals] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const timeLeft = useRef(10);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote updates
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "pos") {
        setBallPositions((prev) => ({ ...prev, [data.playerId]: data.pos }));
      }
    });

    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  useEffect(() => {
    if (!isStarted || finishedRef.current) return;

    const tick = setInterval(() => {
      setBallPositions((prev) => {
        const next = { ...prev };
        players.forEach((p) => {
          if (survivals[p.id] < 0) return; // Already failed

          // Only I can process my own drift and send it
          if (
            myPlayerId !== null &&
            myPlayerId !== undefined &&
            p.id !== myPlayerId
          )
            return;

          const drift = (Math.random() - 0.5) * 4;
          next[p.id] = Math.min(100, Math.max(0, next[p.id] + drift));

          if (myPlayerId !== null && myPlayerId !== undefined) {
            socketService.sendEvent("pos", { playerId: p.id, pos: next[p.id] });
          }
        });
        return next;
      });

      setSurvivals((prev) => {
        const next = { ...prev };
        players.forEach((p) => {
          if (ballPositions[p.id] > 5 && ballPositions[p.id] < 95) {
            next[p.id] += 1;
          }
        });
        return next;
      });

      timeLeft.current -= 0.1;
      if (timeLeft.current <= 0) endGame();
    }, 100);

    return () => clearInterval(tick);
  }, [isStarted, ballPositions, survivals]);

  const handleAdjust = (playerId: number, direction: "L" | "R") => {
    if (!isStarted || finishedRef.current) return;

    // In remote mode, you can only adjust your own ball
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    const nextPos = Math.min(
      100,
      Math.max(0, ballPositions[playerId] + (direction === "L" ? -10 : 10)),
    );
    setBallPositions((prev) => ({
      ...prev,
      [playerId]: nextPos,
    }));
    socketService.sendEvent("pos", { playerId, pos: nextPos });
  };

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    const finalScores = players.map((p) => ({
      playerId: p.id,
      score: survivals[p.id],
    }));
    setTimeout(() => onEnd(finalScores), 1000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden p-2 gap-2">
      {players.map((player) => (
        <div
          key={player.id}
          className="relative flex flex-col items-center justify-center bg-brand-card/30 rounded-3xl border-2 border-white/5 p-4 overflow-hidden"
        >
          <div className="absolute top-4 left-4 flex items-center gap-2">
            <div
              className="w-3 h-3 rounded-full"
              style={{ backgroundColor: player.color }}
            />
            <span className="text-[10px] font-black uppercase opacity-20">
              {player.name} {player.id === myPlayerId && "(YOU)"}
            </span>
          </div>

          <div className="w-full max-w-md h-24 relative flex items-center mb-8 px-12">
            <div className="absolute inset-x-8 h-2 bg-white/5 rounded-full border border-white/5" />
            <div className="absolute left-[15%] w-[0.5px] h-4 bg-brand-accent/40" />
            <div className="absolute right-[15%] w-[0.5px] h-4 bg-brand-accent/40" />

            <motion.div
              animate={{ left: `${ballPositions[player.id]}%` }}
              className={`absolute w-10 h-10 rounded-full shadow-2xl -translate-x-1/2 flex items-center justify-center transition-colors duration-300
                            ${ballPositions[player.id] < 15 || ballPositions[player.id] > 85 ? "bg-brand-accent shadow-brand-accent" : "bg-brand-cyan shadow-brand-cyan"}
                        `}
            >
              <div className="w-6 h-6 bg-white/20 rounded-full animate-pulse" />
            </motion.div>
          </div>

          <div
            className={`grid grid-cols-2 gap-4 w-full px-8 ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 pointer-events-none" : ""}`}
          >
            <button
              onClick={() => handleAdjust(player.id, "L")}
              className="bg-white/5 border border-white/10 py-6 rounded-2xl active:bg-brand-accent font-black cursor-pointer uppercase tracking-widest italic"
            >
              Left
            </button>
            <button
              onClick={() => handleAdjust(player.id, "R")}
              className="bg-white/5 border border-white/10 py-6 rounded-2xl active:bg-brand-accent font-black cursor-pointer uppercase tracking-widest italic"
            >
              Right
            </button>
          </div>

          {isStarted &&
            (ballPositions[player.id] <= 5 ||
              ballPositions[player.id] >= 95) && (
              <div className="absolute inset-0 bg-brand-accent/20 backdrop-blur-[2px] flex items-center justify-center pointer-events-none">
                <span className="text-white font-black italic text-2xl uppercase tracking-tighter drop-shadow-lg">
                  STRAYED
                </span>
              </div>
            )}
        </div>
      ))}

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex flex-col items-center justify-center p-8 text-center">
          <Scale className="text-brand-cyan w-20 h-20 mb-8" />
          <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
            STABLE!
          </h2>
          <p className="text-xl font-bold text-brand-cyan uppercase tracking-widest">
            Keep the pulse in the center!
          </p>
        </div>
      )}
    </div>
  );
}
