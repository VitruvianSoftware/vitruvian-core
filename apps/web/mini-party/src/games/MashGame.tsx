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
import { Flame } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function MashGame({ players, onEnd, myPlayerId }: GameProps) {
  const [mashing, setMashing] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const [timeLeft, setTimeLeft] = useState(5);
  const [isStarted, setIsStarted] = useState(false);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote mashes
    socketService.onRemoteEvent(({ event, data, senderId }) => {
      if (event === "mash") {
        setMashing((prev) => ({
          ...prev,
          [data.playerId]: prev[data.playerId] + 1,
        }));
      }
    });
  }, []);

  useEffect(() => {
    if (isStarted && timeLeft > 0) {
      const timer = setInterval(() => setTimeLeft((t) => t - 1), 1000);
      return () => clearInterval(timer);
    } else if (isStarted && timeLeft === 0) {
      endGame();
    }
  }, [isStarted, timeLeft]);

  // Start sequence
  useEffect(() => {
    const timer = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(timer);
  }, []);

  const handleMash = (playerId: number) => {
    if (!isStarted || timeLeft === 0 || finishedRef.current) return;

    // In remote mode, you can only mash your own button
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    setMashing((prev) => ({ ...prev, [playerId]: prev[playerId] + 1 }));

    // Send to others if in a room
    socketService.sendEvent("mash", { playerId });
  };

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;

    // Scores based on mash count
    const scores = players.map((p) => ({
      playerId: p.id,
      score: mashing[p.id],
    }));

    setTimeout(() => onEnd(scores), 2000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg">
      {/* HUD */}
      <div className="h-28 flex items-center justify-between bg-brand-card/90 backdrop-blur-xl border-b-4 border-brand-accent px-12 relative z-10">
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 bg-brand-accent rounded-xl flex items-center justify-center shadow-[0_0_15px_rgba(255,0,128,0.5)]">
            <Flame className="text-white fill-white w-8 h-8" />
          </div>
          <h2 className="text-4xl font-black italic uppercase tracking-tighter">
            Turbo <span className="text-brand-cyan">Mash</span>
          </h2>
        </div>

        <div className="bg-black/40 px-8 py-3 rounded-2xl border border-white/10 min-w-[120px] text-center">
          {timeLeft > 0 ? (
            <div className="text-5xl font-black tabular-nums italic text-brand-cyan">
              {timeLeft}s
            </div>
          ) : (
            <div className="text-5xl font-black text-brand-accent italic animate-pulse">
              STOP!
            </div>
          )}
        </div>
      </div>

      {/* Play Areas */}
      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => (
          <button
            key={player.id}
            onClick={() => handleMash(player.id)}
            className={`
                relative flex flex-col items-center justify-center gap-6 bg-brand-card/30 rounded-3xl border-2 transition-all cursor-pointer select-none group
                ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 cursor-default grayscale-[0.5]" : "border-white/5 active:bg-white/10 active:scale-[0.98]"}
            `}
          >
            <div className="absolute top-6 left-6 flex items-center gap-3 bg-black/20 px-3 py-1.5 rounded-lg border border-white/5">
              <div
                className="w-2.5 h-2.5 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="font-black text-[9px] uppercase tracking-widest text-white/50">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <div className="relative w-3/4 h-5 bg-black/40 rounded-full overflow-hidden border-2 border-white/5 p-0.5">
              <motion.div
                className="h-full rounded-full transition-all duration-75"
                style={{
                  backgroundColor: player.color,
                  width: `${Math.min(mashing[player.id], 100)}%`,
                  boxShadow: `0 0 15px ${player.color}66`,
                }}
              />
            </div>

            <div className="flex flex-col items-center">
              <span
                className="text-8xl font-black italic tracking-tighter leading-none"
                style={{
                  color: player.color,
                  filter: `drop-shadow(0 0 10px ${player.color}33)`,
                }}
              >
                {mashing[player.id]}
              </span>
              <span className="text-[10px] font-black uppercase tracking-[0.4em] text-white/30 mt-2">
                Activations
              </span>
            </div>

            <AnimatePresence>
              <motion.div
                key={mashing[player.id]}
                initial={{ scale: 1.5, opacity: 0.8 }}
                animate={{ scale: 1, opacity: 0 }}
                className="absolute font-black text-[12rem] pointer-events-none italic opacity-10"
                style={{ color: player.color }}
              >
                HIT
              </motion.div>
            </AnimatePresence>
          </button>
        ))}
      </div>

      <AnimatePresence>
        {!isStarted && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-brand-bg/90 backdrop-blur-xl flex items-center justify-center p-8 text-center"
          >
            <div className="max-w-md">
              <div className="w-24 h-24 bg-brand-accent rounded-3xl flex items-center justify-center mx-auto mb-8 shadow-[0_0_30px_rgba(255,0,128,0.4)]">
                <Flame className="w-14 h-14 text-white fill-white" />
              </div>
              <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4 text-white">
                READY?
              </h2>
              <p className="text-lg font-black uppercase tracking-[0.2em] text-brand-cyan">
                Pulse your button for maximum output!
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
