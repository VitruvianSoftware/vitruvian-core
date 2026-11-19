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
import { Hammer } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function SmashGame({ players, onEnd, myPlayerId }: GameProps) {
  const [moles, setMoles] = useState<number[]>([]);
  const [scores, setScores] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const [isStarted, setIsStarted] = useState(false);
  const finishedRef = useRef(false);
  const timeLeft = useRef(10);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "molesspawn") {
        setMoles(data.moleIndices);
        setTimeout(() => setMoles([]), 800);
      } else if (event === "hit") {
        setScores((prev) => ({ ...prev, [data.playerId]: data.score }));
        setMoles((prev) => prev.filter((h) => h !== data.holeIndex));
      }
    });

    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  useEffect(() => {
    if (!isStarted || finishedRef.current) return;

    const spawnInterval = setInterval(() => {
      if (myPlayerId === 0 || myPlayerId === null || myPlayerId === undefined) {
        const count = Math.floor(Math.random() * 2) + 1;
        const newMoles = Array.from({ length: count }).map(() =>
          Math.floor(Math.random() * 6),
        );
        setMoles(newMoles);
        socketService.sendEvent("molesspawn", { moleIndices: newMoles });

        setTimeout(() => setMoles([]), 800);
      }
    }, 1200);

    const timer = setInterval(() => {
      timeLeft.current -= 1;
      if (timeLeft.current <= 0) endGame();
    }, 1000);

    return () => {
      clearInterval(spawnInterval);
      clearInterval(timer);
    };
  }, [isStarted]);

  const handleSmash = (playerId: number, holeIndex: number) => {
    if (!isStarted || finishedRef.current) return;

    // In remote mode, you can only smash your own grid
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    if (moles.includes(holeIndex)) {
      const newScore = scores[playerId] + 1;
      setScores((prev) => ({ ...prev, [playerId]: newScore }));
      setMoles((prev) => prev.filter((h) => h !== holeIndex));
      socketService.sendEvent("hit", { playerId, holeIndex, score: newScore });
    }
  };

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    const finalScores = players.map((p) => ({
      playerId: p.id,
      score: scores[p.id] * 20,
    }));
    setTimeout(() => onEnd(finalScores), 1000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      <div className="h-20 flex items-center justify-between px-12 bg-brand-card/50 border-b border-white/5">
        <div className="flex items-center gap-4">
          <Hammer className="text-brand-cyan w-8 h-8 rotate-45" />
          <h2 className="text-3xl font-black italic uppercase tracking-tighter">
            SMASH ZONE
          </h2>
        </div>
        <div className="text-4xl font-black tabular-nums italic text-brand-accent">
          {timeLeft.current}s
        </div>
      </div>

      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => (
          <div
            key={player.id}
            className="relative flex flex-col bg-brand-card/30 rounded-3xl border-2 border-white/5 p-4 overflow-hidden"
          >
            <div className="absolute top-2 left-4 flex items-center gap-2">
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="text-[8px] font-black uppercase opacity-20">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <div
              className={`grid grid-cols-3 grid-rows-2 gap-2 mt-4 flex-1 ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 pointer-events-none" : ""}`}
            >
              {[...Array(6)].map((_, i) => (
                <button
                  key={i}
                  onClick={() => handleSmash(player.id, i)}
                  className={`
                                    relative rounded-xl border border-white/5 overflow-hidden transition-all active:scale-95 cursor-pointer
                                    ${moles.includes(i) ? "bg-brand-cyan shadow-[0_0_15px_#00F2FF]" : "bg-black/20 hover:bg-white/5"}
                                `}
                >
                  <AnimatePresence>
                    {moles.includes(i) && (
                      <motion.div
                        initial={{ y: 20, opacity: 0 }}
                        animate={{ y: 0, opacity: 1 }}
                        exit={{ scale: 2, opacity: 0 }}
                        className="w-full h-full flex items-center justify-center font-black text-brand-bg"
                      >
                        !!!
                      </motion.div>
                    )}
                  </AnimatePresence>
                </button>
              ))}
            </div>

            <div
              className="absolute bottom-2 right-4 text-3xl font-black italic opacity-20 pointer-events-none"
              style={{ color: player.color }}
            >
              {scores[player.id]}
            </div>
          </div>
        ))}
      </div>

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex flex-col items-center justify-center p-8 text-center text-white">
          <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
            SMASH!
          </h2>
          <p className="text-xl font-bold text-brand-cyan uppercase tracking-widest">
            Hit the glowing squares!
          </p>
        </div>
      )}
    </div>
  );
}
