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
import { Fuel } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function FuelGame({ players, onEnd, myPlayerId }: GameProps) {
  const [fuelLevels, setFuelLevels] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const [isPressing, setIsPressing] = useState<Record<number, boolean>>(
    Object.fromEntries(players.map((p) => [p.id, false])),
  );
  const [explosions, setExplosions] = useState<number[]>([]);
  const [isStarted, setIsStarted] = useState(false);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "press") {
        setIsPressing((prev) => ({ ...prev, [data.playerId]: data.value }));
      } else if (event === "boom") {
        setExplosions((prev) => [...prev, data.playerId]);
      }
    });

    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  useEffect(() => {
    if (!isStarted || finishedRef.current) return;

    const tick = setInterval(() => {
      setFuelLevels((prev) => {
        const next = { ...prev };
        players.forEach((p) => {
          if (explosions.includes(p.id)) return;
          if (isPressing[p.id]) {
            next[p.id] = Math.min(110, next[p.id] + 1.5);
            if (next[p.id] > 100) {
              setExplosions((ex) => {
                if (ex.includes(p.id)) return ex;
                if (
                  myPlayerId !== null &&
                  myPlayerId !== undefined &&
                  p.id === myPlayerId
                ) {
                  socketService.sendEvent("boom", { playerId: p.id });
                }
                return [...ex, p.id];
              });
              next[p.id] = 0; // Boom
            }
          }
        });
        return next;
      });
    }, 50);

    return () => clearInterval(tick);
  }, [isStarted, isPressing, explosions, myPlayerId]);

  const handlePress = (playerId: number, value: boolean) => {
    if (!isStarted || finishedRef.current || explosions.includes(playerId))
      return;

    // In remote mode, you can only press your own button
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    setIsPressing((prev) => ({ ...prev, [playerId]: value }));
    socketService.sendEvent("press", { playerId, value });
  };

  useEffect(() => {
    if (isStarted) {
      const timer = setTimeout(() => endGame(), 6000);
      return () => clearTimeout(timer);
    }
  }, [isStarted]);

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    const finalScores = players.map((p) => ({
      playerId: p.id,
      score: explosions.includes(p.id) ? 0 : Math.round(fuelLevels[p.id]),
    }));
    setTimeout(() => onEnd(finalScores), 1500);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      <div className="h-24 flex items-center justify-center border-b border-white/5 bg-brand-card/30">
        <h2 className="text-4xl font-black italic uppercase tracking-tighter">
          TURBO PUMP
        </h2>
      </div>

      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => (
          <div
            key={player.id}
            className="relative bg-brand-card/30 rounded-3xl border-2 border-white/5 p-6 flex flex-col items-center justify-between overflow-hidden"
          >
            <div className="absolute top-4 left-4 flex items-center gap-2">
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="text-[8px] font-black uppercase opacity-20">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <div className="w-16 h-48 bg-black/40 rounded-2xl border border-white/10 relative p-1.5 overflow-hidden">
              <div className="absolute top-1/4 left-0 right-0 h-[1px] bg-brand-accent/20" />
              <div className="absolute top-0 left-0 right-0 h-10 bg-brand-accent/30 animate-pulse pointer-events-none" />
              <motion.div
                animate={{ height: `${fuelLevels[player.id]}%` }}
                className="absolute bottom-0 left-0 right-0 transition-all duration-75"
                style={{
                  backgroundColor: player.color,
                  boxShadow: `0 0 30px ${player.color}88`,
                }}
              />
              <div className="absolute inset-0 flex flex-col justify-between p-2 pointer-events-none">
                <span className="text-[6px] font-bold opacity-30">DANGER</span>
                <span className="text-[6px] font-bold opacity-30 mt-auto">
                  MIN
                </span>
              </div>
            </div>

            <button
              onMouseDown={() => handlePress(player.id, true)}
              onMouseUp={() => handlePress(player.id, false)}
              onTouchStart={() => handlePress(player.id, true)}
              onTouchEnd={() => handlePress(player.id, false)}
              className={`
                            w-full py-6 rounded-2xl font-black text-xl italic uppercase tracking-widest transition-all cursor-pointer select-none
                            ${explosions.includes(player.id) ? "bg-brand-accent text-white animate-shake" : isPressing[player.id] ? "bg-brand-cyan scale-95 shadow-[0_0_20px_#00F2FF]" : "bg-white/10 hover:bg-white/20"}
                        `}
            >
              {explosions.includes(player.id) ? "OVERHEAT" : "PUMP"}
            </button>

            <AnimatePresence>
              {explosions.includes(player.id) && (
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 2 }}
                  className="absolute inset-0 bg-brand-accent/40 flex items-center justify-center pointer-events-none"
                >
                  <span className="text-4xl font-black italic drop-shadow-2xl">
                    BOOM!
                  </span>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        ))}
      </div>

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex flex-col items-center justify-center p-8 text-center text-white">
          <Fuel className="text-brand-accent w-20 h-20 mb-8" />
          <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
            PUMP!
          </h2>
          <p className="text-xl font-bold text-brand-cyan uppercase tracking-widest">
            Hold to fill, release to stay safe!
          </p>
          <p className="text-sm font-black uppercase tracking-[0.4em] text-white/40 mt-8">
            DO NOT EXCEED 100%
          </p>
        </div>
      )}
    </div>
  );
}
