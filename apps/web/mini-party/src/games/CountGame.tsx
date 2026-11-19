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
import { Eye } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function CountGame({ players, onEnd, myPlayerId }: GameProps) {
  const [dots, setDots] = useState<{ id: number; x: number; y: number }[]>([]);
  const [isShowing, setIsShowing] = useState(false);
  const [isSelecting, setIsSelecting] = useState(false);
  const [playerGuess, setPlayerGuess] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const correctCount = useRef(0);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote guesses
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "guess") {
        setPlayerGuess((prev) => ({ ...prev, [data.playerId]: data.value }));
      } else if (event === "setup") {
        correctCount.current = data.count;
        setDots(data.dots);
      }
    });

    if (myPlayerId === 0 || myPlayerId === null || myPlayerId === undefined) {
      const count = Math.floor(Math.random() * 8) + 5; // 5-12 dots
      correctCount.current = count;
      const newDots = Array.from({ length: count }).map((_, i) => ({
        id: i,
        x: Math.random() * 80 + 10,
        y: Math.random() * 80 + 10,
      }));
      setDots(newDots);
      socketService.sendEvent("setup", { count, dots: newDots });
    }

    setTimeout(() => {
      setIsShowing(true);
      setTimeout(() => {
        setIsShowing(false);
        setIsSelecting(true);
      }, 1500); // Show for 1.5s
    }, 1500);
  }, []);

  const handleGuess = (playerId: number, delta: number) => {
    if (!isSelecting || finishedRef.current) return;

    // In remote mode, you can only change your own guess
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    const newValue = Math.min(20, Math.max(0, playerGuess[playerId] + delta));
    setPlayerGuess((prev) => ({ ...prev, [playerId]: newValue }));
    socketService.sendEvent("guess", { playerId, value: newValue });
  };

  const submitGuess = (playerId: number) => {
    // In this simple version, players just adjust and we auto-end after timeout or button press
    // For a faster party feel, let's add a "CONFIRM" button
  };

  useEffect(() => {
    if (isSelecting) {
      const timer = setTimeout(() => {
        endGame();
      }, 5000);
      return () => clearTimeout(timer);
    }
  }, [isSelecting]);

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;

    const scores = players.map((p) => {
      const diff = Math.abs(correctCount.current - playerGuess[p.id]);
      const score = Math.max(0, 100 - diff * 25);
      return { playerId: p.id, score };
    });

    setTimeout(() => onEnd(scores), 2000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      <div className="h-1/2 flex items-center justify-center bg-black/40 relative">
        <AnimatePresence>
          {isShowing &&
            dots.map((dot) => (
              <motion.div
                key={dot.id}
                initial={{ scale: 0, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                exit={{ scale: 0, opacity: 0 }}
                className="absolute w-6 h-6 bg-brand-cyan rounded-full border-2 border-white shadow-[0_0_15px_rgba(0,242,255,0.5)]"
                style={{ left: `${dot.x}%`, top: `${dot.y}%` }}
              />
            ))}
          {!isShowing && !isSelecting && (
            <div className="text-4xl font-black italic uppercase tracking-tighter text-white animate-pulse">
              EYES UP
            </div>
          )}
          {isSelecting && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="flex flex-col items-center"
            >
              <span className="text-xl font-bold text-brand-cyan uppercase tracking-widest mb-2">
                How many?
              </span>
              <div className="flex gap-2">
                {[...Array(3)].map((_, i) => (
                  <div
                    key={i}
                    className="w-2 h-2 rounded-full bg-brand-cyan/20 animate-bounce"
                    style={{ animationDelay: `${i * 0.2}s` }}
                  />
                ))}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-4 gap-4">
        {players.map((player) => (
          <div
            key={player.id}
            className="relative flex flex-col items-center justify-center rounded-3xl bg-brand-card/40 border-2 border-white/5 p-4"
          >
            <div className="absolute top-4 left-4 flex items-center gap-2">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="text-[8px] font-black uppercase opacity-40">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <div
              className={`flex items-center gap-8 ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 pointer-events-none" : ""}`}
            >
              <button
                onClick={() => handleGuess(player.id, -1)}
                className="w-12 h-12 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-2xl font-black active:bg-brand-accent cursor-pointer"
              >
                -
              </button>
              <div
                className="text-6xl font-black italic"
                style={{ color: player.color }}
              >
                {playerGuess[player.id]}
              </div>
              <button
                onClick={() => handleGuess(player.id, 1)}
                className="w-12 h-12 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-2xl font-black active:bg-brand-green cursor-pointer"
              >
                +
              </button>
            </div>

            {finishedRef.current && (
              <div className="mt-4 text-[10px] font-black uppercase tracking-widest">
                Target:{" "}
                <span className="text-brand-cyan">{correctCount.current}</span>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
