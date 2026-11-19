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
import { Crosshair } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function TargetGame({ players, onEnd, myPlayerId }: GameProps) {
  const [targetPos, setTargetPos] = useState({ x: 50, y: 50, size: 20 });
  const [isStarted, setIsStarted] = useState(false);
  const [scores, setScores] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const timeLeft = useRef(8);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "hit") {
        setScores((prev) => ({
          ...prev,
          [data.playerId]: prev[data.playerId] + 1,
        }));
        if (data.newPos) setTargetPos(data.newPos);
      }
    });
  }, []);

  useEffect(() => {
    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  useEffect(() => {
    if (!isStarted || finishedRef.current) return;

    const moveInterval = setInterval(() => {
      setTargetPos({
        x: Math.random() * 70 + 15,
        y: Math.random() * 70 + 15,
        size: Math.random() * 10 + 5,
      });
    }, 1000);

    const gameTimer = setInterval(() => {
      timeLeft.current -= 1;
      if (timeLeft.current <= 0) {
        endGame();
      }
    }, 1000);

    return () => {
      clearInterval(moveInterval);
      clearInterval(gameTimer);
    };
  }, [isStarted]);

  const handleHit = (playerId: number) => {
    if (!isStarted || finishedRef.current) return;

    // In remote mode, you can only hit your own button
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    setScores((prev) => ({ ...prev, [playerId]: prev[playerId] + 1 }));

    const newPos = {
      x: Math.random() * 70 + 15,
      y: Math.random() * 70 + 15,
      size: Math.random() * 10 + 5,
    };

    setTargetPos(newPos);
    socketService.sendEvent("hit", { playerId, newPos });
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
      {/* SHARED TARGET AREA */}
      <div className="h-1/2 flex items-center justify-center bg-black/50 relative overflow-hidden border-b-4 border-brand-accent">
        <div
          className="absolute inset-0 opacity-10"
          style={{
            backgroundImage:
              "radial-gradient(circle, #fff 1px, transparent 1px)",
            backgroundSize: "30px 30px",
          }}
        />

        <AnimatePresence>
          {isStarted && !finishedRef.current && (
            <motion.div
              key={`${targetPos.x}-${targetPos.y}`}
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              className="absolute w-20 h-20 flex items-center justify-center pointer-events-none"
              style={{
                left: `${targetPos.x}%`,
                top: `${targetPos.y}%`,
                marginLeft: "-40px",
                marginTop: "-40px",
              }}
            >
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ repeat: Infinity, duration: 2, ease: "linear" }}
                className="absolute inset-0 border-4 border-dashed border-brand-cyan rounded-full opacity-50"
              />
              <div className="w-12 h-12 bg-white rounded-full flex items-center justify-center shadow-[0_0_30px_#fff]">
                <Crosshair className="text-brand-bg w-8 h-8" strokeWidth={3} />
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        <div className="absolute top-4 right-4 bg-brand-accent/20 px-4 py-1 rounded-full border border-brand-accent/30">
          <span className="text-brand-accent font-black italic">
            {Math.max(0, timeLeft.current)}s
          </span>
        </div>
      </div>

      {/* CONTROLS */}
      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => (
          <button
            key={player.id}
            onClick={() => handleHit(player.id)}
            className={`
                        relative flex flex-col items-center justify-center rounded-2xl transition-all cursor-pointer group
                        ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 grayscale-[0.5] bg-brand-card/20 border border-white/5" : "bg-brand-card/40 border-2 border-white/5 active:bg-brand-accent active:scale-95"}
                    `}
          >
            <div className="absolute top-4 left-4 flex items-center gap-2">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="text-[9px] font-black uppercase opacity-40">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <div className="flex flex-col items-center">
              <span
                className="text-5xl font-black italic tracking-tighter"
                style={{ color: player.color }}
              >
                {scores[player.id]}
              </span>
              <span className="text-[10px] font-bold uppercase tracking-[0.3em] text-white/30">
                HITS
              </span>
            </div>
          </button>
        ))}
      </div>

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex items-center justify-center p-8 text-center">
          <div className="max-w-md">
            <div className="w-20 h-20 bg-brand-cyan rounded-2xl flex items-center justify-center mx-auto mb-8 shadow-[0_0_20px_#00F2FF]">
              <Crosshair className="text-brand-bg w-12 h-12" strokeWidth={3} />
            </div>
            <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
              SNIPE!
            </h2>
            <p className="text-lg font-black uppercase tracking-[0.2em] text-brand-cyan">
              Shared target! Tap to fire!
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
