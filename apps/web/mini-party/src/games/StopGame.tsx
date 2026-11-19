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
import { Timer } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function StopGame({ players, onEnd, myPlayerId }: GameProps) {
  const [time, setTime] = useState(0);
  const [isStarted, setIsStarted] = useState(false);
  const [results, setResults] = useState<{ playerId: number; time: number }[]>(
    [],
  );
  const intervalRef = useRef<number | null>(null);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "stop") {
        const { playerId, time: stopTime } = data;
        setResults((prev) => {
          if (prev.some((r) => r.playerId === playerId)) return prev;
          return [...prev, { playerId, time: stopTime }];
        });
      }
    });
  }, []);

  useEffect(() => {
    const startTimer = setTimeout(() => setIsStarted(true), 2000);
    return () => {
      clearTimeout(startTimer);
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, []);

  useEffect(() => {
    if (isStarted && !finishedRef.current) {
      intervalRef.current = window.setInterval(() => {
        setTime((t) => {
          if (t >= 10) {
            endGame(results);
            return 10;
          }
          return t + 0.01;
        });
      }, 10);
      return () => {
        if (intervalRef.current) clearInterval(intervalRef.current);
      };
    }
  }, [isStarted, results]);

  const handleStop = (playerId: number) => {
    if (
      !isStarted ||
      finishedRef.current ||
      results.some((r) => r.playerId === playerId)
    )
      return;

    // In remote mode, only allow stopping your own button
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    const stopTime = time;
    setResults((prev) => [...prev, { playerId, time: stopTime }]);
    socketService.sendEvent("stop", { playerId, time: stopTime });

    if (results.length + 1 === players.length) {
      endGame([...results, { playerId, time: stopTime }]);
    }
  };

  const endGame = (finalResults: typeof results) => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    if (intervalRef.current) clearInterval(intervalRef.current);

    const scores = players.map((p) => {
      const result = finalResults.find((r) => r.playerId === p.id);
      const diff = result ? Math.abs(5.0 - result.time) : 10;
      // Score: 100 max, decreases by 20 for every second away from 5.00
      const score = Math.max(0, Math.round(100 - diff * 20));
      return { playerId: p.id, score };
    });

    setTimeout(() => onEnd(scores), 2000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,_var(--color-brand-cyan)_0%,_transparent_70%)] opacity-5" />

      <div className="h-48 flex flex-col items-center justify-center border-b border-white/10 bg-brand-card/30">
        <div className="flex items-center gap-4 mb-4">
          <Timer className="w-8 h-8 text-brand-cyan animate-pulse" />
          <span className="text-2xl font-black italic uppercase tracking-tighter">
            STOP AT 5.00
          </span>
        </div>
        <div
          className={`text-8xl font-black tabular-nums italic ${time > 5 ? "text-brand-accent" : "text-white"}`}
        >
          {time < 2 ? time.toFixed(2) : "?.??"}
        </div>
        <p className="text-[10px] font-bold text-white/30 uppercase tracking-[0.5em] mt-4">
          Digits hidden after 2.0s
        </p>
      </div>

      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-4 gap-4">
        {players.map((player) => (
          <button
            key={player.id}
            onClick={() => handleStop(player.id)}
            className={`
                group relative flex flex-col items-center justify-center rounded-3xl border-2 transition-all cursor-pointer
                ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 grayscale-[0.5]" : "border-white/5 bg-brand-card/40 active:scale-95"}
            `}
          >
            <div className="absolute top-6 left-6 flex items-center gap-2">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="text-[10px] font-black uppercase opacity-40">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <AnimatePresence mode="wait">
              {results.some((r) => r.playerId === player.id) ? (
                <motion.div
                  initial={{ scale: 0.5, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  className="text-center"
                >
                  <div className="text-6xl font-black italic mb-2">
                    {results
                      .find((r) => r.playerId === player.id)
                      ?.time.toFixed(2)}
                  </div>
                  <div className="text-[10px] font-bold uppercase tracking-widest text-brand-cyan">
                    LOCKED
                  </div>
                </motion.div>
              ) : (
                <div className="text-white/10 group-hover:text-white/20 transition-colors uppercase font-black text-4xl italic">
                  STOP!
                </div>
              )}
            </AnimatePresence>
          </button>
        ))}
      </div>

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-8 text-center backdrop-blur-xl">
          <div>
            <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
              LOCK IN
            </h2>
            <p className="text-lg font-bold text-brand-cyan uppercase tracking-widest">
              Stop the clock as close to 5.00 as possible!
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
