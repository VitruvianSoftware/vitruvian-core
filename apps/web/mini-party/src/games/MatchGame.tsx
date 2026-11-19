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
import { Palette } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

const COLORS = ["#FF0080", "#00F2FF", "#4ECCA3", "#FFD700"];

export default function MatchGame({ players, onEnd, myPlayerId }: GameProps) {
  const [targetColor, setTargetColor] = useState(COLORS[0]);
  const [isStarted, setIsStarted] = useState(false);
  const [playerScores, setPlayerScores] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const timeLeft = useRef(10);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "score") {
        setPlayerScores((prev) => ({ ...prev, [data.playerId]: data.score }));
      } else if (event === "target") {
        setTargetColor(data.color);
      }
    });

    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  useEffect(() => {
    if (!isStarted || finishedRef.current) return;

    const colorInterval = setInterval(() => {
      if (myPlayerId === 0 || myPlayerId === null || myPlayerId === undefined) {
        const nextColor = COLORS[Math.floor(Math.random() * COLORS.length)];
        setTargetColor(nextColor);
        socketService.sendEvent("target", { color: nextColor });
      }
    }, 1500);

    const gameTimer = setInterval(() => {
      timeLeft.current -= 1;
      if (timeLeft.current <= 0) endGame();
    }, 1000);

    return () => {
      clearInterval(colorInterval);
      clearInterval(gameTimer);
    };
  }, [isStarted]);

  const handleTap = (playerId: number, colorIndex: number) => {
    if (!isStarted || finishedRef.current) return;

    // In remote mode, you can only tap your own buttons
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    let newScore = playerScores[playerId];
    if (COLORS[colorIndex] === targetColor) {
      newScore += 1;
    } else {
      newScore = Math.max(0, newScore - 1);
    }

    setPlayerScores((prev) => ({ ...prev, [playerId]: newScore }));
    socketService.sendEvent("score", { playerId, score: newScore });
  };

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    const finalScores = players.map((p) => ({
      playerId: p.id,
      score: playerScores[p.id] * 20,
    }));
    setTimeout(() => onEnd(finalScores), 1000);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      {/* SHARED TARGET COLOR AREA */}
      <div
        className="h-1/3 flex flex-col items-center justify-center relative transition-colors duration-500"
        style={{ backgroundColor: `${targetColor}22` }}
      >
        <div className="absolute top-4 right-4 bg-black/40 px-6 py-2 rounded-2xl border border-white/10">
          <span className="text-3xl font-black italic tabular-nums">
            {timeLeft.current}s
          </span>
        </div>

        <motion.div
          key={targetColor}
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          className="w-32 h-32 rounded-3xl shadow-[0_0_50px_rgba(255,255,255,0.2)] flex items-center justify-center border-4 border-white/20"
          style={{ backgroundColor: targetColor }}
        >
          <Palette
            className="text-white mix-blend-difference w-16 h-16"
            strokeWidth={3}
          />
        </motion.div>
        <h2 className="mt-4 text-[10px] font-black uppercase tracking-[0.5em] text-white/40">
          Match the Core
        </h2>
      </div>

      {/* PLAYER GRID */}
      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => (
          <div
            key={player.id}
            className="relative flex flex-col bg-brand-card/40 rounded-3xl border-2 border-white/5 p-4 overflow-hidden"
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

            <div
              className={`flex-grow grid grid-cols-2 grid-rows-2 gap-2 mt-4 pt-4 ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 pointer-events-none" : ""}`}
            >
              {COLORS.map((color, i) => (
                <button
                  key={i}
                  onClick={() => handleTap(player.id, i)}
                  className="rounded-2xl flex items-center justify-center active:scale-90 transition-all cursor-pointer shadow-lg border-2 border-white/5"
                  style={{ backgroundColor: color }}
                >
                  <div className="w-1/2 h-1/2 bg-white/20 rounded-lg backdrop-blur-sm" />
                </button>
              ))}
            </div>

            <div
              className="absolute bottom-4 right-4 text-4xl font-black italic opacity-20 pointer-events-none"
              style={{ color: player.color }}
            >
              {playerScores[player.id]}
            </div>
          </div>
        ))}
      </div>

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex items-center justify-center p-8 text-center text-white">
          <div>
            <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
              COLOR!
            </h2>
            <p className="text-lg font-black uppercase tracking-[0.2em] text-brand-cyan">
              Tap the grid to match the target!
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
