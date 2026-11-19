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
import { MoveHorizontal } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function TugGame({ players, onEnd, myPlayerId }: GameProps) {
  const [position, setPosition] = useState(50); // 0 to 100
  const [isStarted, setIsStarted] = useState(false);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote pulls
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "pull") {
        const { position: newPos } = data;
        setPosition(newPos);
        if (newPos <= 5 || newPos >= 95) {
          endGame(newPos);
        }
      }
    });
  }, []);

  // Divide players into two teams: Team A (0,1) vs Team B (2,3 or just 1 vs 1)
  const teamA = players.filter((_, i) => i < Math.ceil(players.length / 2));
  const teamB = players.filter((_, i) => i >= Math.ceil(players.length / 2));

  useEffect(() => {
    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  const handlePull = (playerId: number) => {
    if (!isStarted || finishedRef.current) return;

    // In remote mode, you can only pull for your own button
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    const isTeamA = teamA.some((p) => p.id === playerId);
    const nextPos = isTeamA ? position - 2 : position + 2;

    setPosition(nextPos);
    socketService.sendEvent("pull", { position: nextPos });

    if (nextPos <= 5 || nextPos >= 95) {
      endGame(nextPos);
    }
  };

  const endGame = (finalPos: number) => {
    if (finishedRef.current) return;
    finishedRef.current = true;

    const winnerTeam = finalPos <= 5 ? "A" : "B";
    const scores = players.map((p) => {
      const isTeamA = teamA.some((tp) => tp.id === p.id);
      const win =
        (winnerTeam === "A" && isTeamA) || (winnerTeam === "B" && !isTeamA);
      return { playerId: p.id, score: win ? 100 : 0 };
    });

    setTimeout(() => onEnd(scores), 1500);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      <div className="h-1/3 flex flex-col items-center justify-center border-b border-white/5 relative bg-brand-card/20">
        <h2 className="text-4xl font-black italic uppercase tracking-tighter mb-4">
          TEAM BATTLE
        </h2>
        <div className="w-full h-24 relative flex items-center px-12">
          <div className="absolute left-12 right-12 h-2 bg-white/10 rounded-full" />
          <div className="absolute left-1/2 w-1 h-32 bg-brand-accent/50 -translate-x-1/2 top-1/2 -translate-y-1/2" />

          <motion.div
            animate={{ left: `${position}%` }}
            className="absolute w-12 h-12 bg-white rounded-xl shadow-[0_0_30px_#fff] flex items-center justify-center -translate-x-1/2"
          >
            <MoveHorizontal className="text-brand-bg w-8 h-8" />
          </motion.div>

          <div className="flex justify-between w-full relative z-10 px-4">
            <div className="flex gap-2">
              {teamA.map((p) => (
                <div
                  key={p.id}
                  className="w-4 h-4 rounded-full shadow-lg"
                  style={{ backgroundColor: p.color }}
                />
              ))}
            </div>
            <div className="flex gap-2">
              {teamB.map((p) => (
                <div
                  key={p.id}
                  className="w-4 h-4 rounded-full shadow-lg"
                  style={{ backgroundColor: p.color }}
                />
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className="flex-1 grid grid-cols-2 grid-rows-2 gap-2 p-2">
        {players.map((player) => (
          <button
            key={player.id}
            onClick={() => handlePull(player.id)}
            className={`
                        relative flex flex-col items-center justify-center rounded-2xl transition-all cursor-pointer group
                        ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 grayscale-[0.5] bg-brand-card/20 border border-white/5" : "bg-brand-card/40 border-2 border-white/5 active:bg-white/10 active:scale-[0.98]"}
                    `}
          >
            <div className="absolute top-4 left-4 flex items-center gap-2">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: player.color }}
              />
              <span className="text-[10px] font-black uppercase opacity-20 tracking-widest">
                {player.name} {player.id === myPlayerId && "(YOU)"}
              </span>
            </div>

            <div className="flex flex-col items-center">
              <span
                className="text-5xl font-black italic uppercase tracking-tighter"
                style={{ color: player.color }}
              >
                {teamA.some((p) => p.id === player.id)
                  ? "PULL LEFT"
                  : "PULL RIGHT"}
              </span>
              <div className="mt-4 flex gap-1">
                {[...Array(5)].map((_, i) => (
                  <div key={i} className="w-1.5 h-6 bg-white/10 rounded-full" />
                ))}
              </div>
            </div>
          </button>
        ))}
      </div>

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex items-center justify-center p-8 text-center">
          <div className="max-w-md">
            <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
              TUG!
            </h2>
            <p className="text-xl font-bold text-brand-cyan uppercase tracking-widest">
              Team {teamA.map((p) => p.id + 1).join("+")} VS Team{" "}
              {teamB.map((p) => p.id + 1).join("+")}
            </p>
            <p className="text-sm font-black uppercase tracking-[0.4em] text-white/40 mt-8">
              MASH TO PULL TOWARDS YOUR SIDE
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
