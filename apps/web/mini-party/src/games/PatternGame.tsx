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

import { useState, useEffect, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Player } from "../types";
import { Square, Triangle, Circle, Hexagon } from "lucide-react";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
}

const SHAPES = [
  { id: 0, icon: Square, label: "SQ" },
  { id: 1, icon: Triangle, label: "TR" },
  { id: 2, icon: Circle, label: "CI" },
  { id: 3, icon: Hexagon, label: "HX" },
];

export default function PatternGame({ players, onEnd }: GameProps) {
  const [pattern, setPattern] = useState<number[]>([]);
  const [playerInputs, setPlayerInputs] = useState<Record<number, number[]>>(
    Object.fromEntries(players.map((p) => [p.id, []])),
  );
  const [isShowingPattern, setIsShowingPattern] = useState(true);
  const [currentDisplayIndex, setCurrentDisplayIndex] = useState(-1);
  const [results, setResults] = useState<{ playerId: number; time: number }[]>(
    [],
  );
  const startTime = useRef<number>(0);
  const finishedRef = useRef(false);

  // Generate pattern
  useEffect(() => {
    const newPattern = Array.from({ length: 4 }).map(() =>
      Math.floor(Math.random() * 4),
    );
    setPattern(newPattern);

    // Pattern display sequence
    let i = 0;
    const interval = setInterval(() => {
      if (i < newPattern.length) {
        setCurrentDisplayIndex(i);
        i++;
      } else {
        clearInterval(interval);
        setTimeout(() => {
          setIsShowingPattern(false);
          setCurrentDisplayIndex(-1);
          startTime.current = Date.now();
        }, 800);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  const handleInput = useCallback(
    (playerId: number, shapeId: number) => {
      if (
        isShowingPattern ||
        finishedRef.current ||
        results.some((r) => r.playerId === playerId)
      )
        return;

      const currentInputs = playerInputs[playerId];
      const expectedShape = pattern[currentInputs.length];

      if (shapeId === expectedShape) {
        const nextInputs = [...currentInputs, shapeId];
        setPlayerInputs((prev) => ({ ...prev, [playerId]: nextInputs }));

        if (nextInputs.length === pattern.length) {
          const completionTime = Date.now() - startTime.current;
          const newResults = [...results, { playerId, time: completionTime }];
          setResults(newResults);

          if (newResults.length === players.length) {
            endGame(newResults);
          }
        }
      } else {
        // Wrong input - reset
        setPlayerInputs((prev) => ({ ...prev, [playerId]: [] }));
      }
    },
    [isShowingPattern, playerInputs, pattern, results, players],
  );

  const endGame = (finalResults: typeof results) => {
    if (finishedRef.current) return;
    finishedRef.current = true;

    // Scores based on completion speed
    const scores = players.map((p) => {
      const rankIndex = finalResults
        .sort((a, b) => a.time - b.time)
        .findIndex((r) => r.playerId === p.id);
      let score = 0;
      if (rankIndex === 0) score = 100;
      else if (rankIndex === 1) score = 75;
      else if (rankIndex === 2) score = 50;
      else if (rankIndex === 3) score = 25;
      return { playerId: p.id, score };
    });

    setTimeout(() => onEnd(scores), 2000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg">
      {/* Pattern Display */}
      <div className="h-1/3 flex items-center justify-center border-b border-white/5 bg-brand-card/20 gap-8 relative overflow-hidden">
        {/* Animated background lines */}
        <div className="absolute inset-0 opacity-10 pointer-events-none">
          <div className="absolute top-0 left-1/4 w-[1px] h-full bg-brand-cyan" />
          <div className="absolute top-0 left-2/4 w-[1px] h-full bg-brand-cyan" />
          <div className="absolute top-0 left-3/4 w-[1px] h-full bg-brand-cyan" />
        </div>

        {pattern.map((shapeId, i) => {
          const ShapeIcon = SHAPES[shapeId].icon;
          const isActive = currentDisplayIndex === i;
          const isCompleted =
            !isShowingPattern &&
            players.every((p) => playerInputs[p.id].length > i);

          return (
            <motion.div
              key={i}
              animate={{
                scale: isActive ? 1.3 : 1,
                opacity: isShowingPattern
                  ? isActive
                    ? 1
                    : 0.2
                  : isCompleted
                    ? 1
                    : 0.05,
              }}
              className={`w-28 h-28 flex items-center justify-center rounded-2xl border-4 transition-all duration-300 ${isActive ? "bg-brand-cyan border-white shadow-[0_0_30px_rgba(0,242,255,0.5)]" : "border-white/10"}`}
            >
              <ShapeIcon
                className={`w-14 h-14 ${isActive ? "text-brand-bg" : "text-white"}`}
                strokeWidth={3}
              />
            </motion.div>
          );
        })}
      </div>

      {/* Play Areas */}
      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => {
          const currentCount = playerInputs[player.id].length;
          const hasFinished = results.some((r) => r.playerId === player.id);

          return (
            <div
              key={player.id}
              className="relative flex bg-brand-card/40 rounded-3xl border-2 border-white/5 p-6 gap-6 overflow-hidden"
            >
              <div className="absolute top-4 left-4 flex items-center gap-2">
                <div
                  className="w-3 h-3 rounded-full"
                  style={{ backgroundColor: player.color }}
                />
                <span className="text-[10px] font-black uppercase opacity-30 tracking-widest">
                  {player.name}
                </span>
              </div>

              <div className="flex-1 grid grid-cols-2 gap-3">
                {SHAPES.map((shape) => {
                  const Icon = shape.icon;
                  return (
                    <button
                      key={shape.id}
                      onClick={() => handleInput(player.id, shape.id)}
                      className={`
                                        flex flex-col items-center justify-center rounded-2xl border-2 transition-all active:scale-95 cursor-pointer group
                                        ${hasFinished ? "opacity-20 pointer-events-none" : "bg-white/5 border-white/10 hover:border-brand-cyan/50 hover:bg-brand-cyan/5 active:bg-brand-cyan/20"}
                                    `}
                    >
                      <Icon
                        className="w-8 h-8 mb-1 group-hover:text-brand-cyan transition-colors"
                        strokeWidth={3}
                      />
                      <span className="text-[9px] font-black font-mono tracking-widest opacity-40 uppercase">
                        {shape.label}
                      </span>
                    </button>
                  );
                })}
              </div>

              <div className="w-20 flex flex-col gap-3 py-2">
                {pattern.map((_, i) => (
                  <div
                    key={i}
                    className={`w-full flex-1 transition-all rounded-lg border-2 ${i < currentCount ? "bg-brand-green border-white shadow-[0_0_15px_rgba(78,204,163,0.5)]" : "bg-black/20 border-white/5"}`}
                  />
                ))}
              </div>

              {hasFinished && (
                <div className="absolute inset-0 bg-brand-bg/80 backdrop-blur-sm flex items-center justify-center z-10">
                  <motion.div
                    initial={{ scale: 0.5, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    className="text-4xl font-black italic tracking-tighter"
                    style={{ color: player.color }}
                  >
                    UPLOAD_OK
                  </motion.div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      <AnimatePresence>
        {isShowingPattern && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-brand-bg/90 backdrop-blur-xl flex flex-col items-center justify-center p-8 text-center"
          >
            <motion.h2
              animate={{ scale: [1, 1.05, 1] }}
              transition={{ repeat: Infinity, duration: 1.5 }}
              className="text-7xl font-black italic uppercase tracking-tighter mb-4 text-white drop-shadow-[0_0_20px_rgba(255,255,255,0.2)]"
            >
              ECHO SCAN
            </motion.h2>
            <p className="text-xl font-bold uppercase tracking-[0.3em] text-brand-cyan">
              Syncing sequence data...
            </p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
