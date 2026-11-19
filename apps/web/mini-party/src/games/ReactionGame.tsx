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
import { Zap } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function ReactionGame({
  players,
  onEnd,
  myPlayerId,
}: GameProps) {
  const [status, setStatus] = useState<"WAIT" | "READY" | "GO" | "FINISHED">(
    "WAIT",
  );
  const [results, setResults] = useState<{ playerId: number; time: number }[]>(
    [],
  );
  const [disqualified, setDisqualified] = useState<number[]>([]);

  const startTime = useRef<number>(0);
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "hit") {
        const { playerId, time } = data;
        setResults((prev) => {
          if (prev.some((r) => r.playerId === playerId)) return prev;
          return [...prev, { playerId, time }];
        });
      } else if (event === "foul") {
        setDisqualified((prev) => [...prev, data.playerId]);
      }
    });
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      setStatus("READY");
      const secondTimer = setTimeout(
        () => {
          setStatus("GO");
          startTime.current = Date.now();
        },
        Math.random() * 3000 + 1000,
      ); // 1-4 seconds
      return () => clearTimeout(secondTimer);
    }, 1500);

    return () => clearTimeout(timer);
  }, []);

  const handleTap = useCallback(
    (playerId: number) => {
      if (
        finishedRef.current ||
        disqualified.includes(playerId) ||
        results.some((r) => r.playerId === playerId)
      )
        return;

      // In remote mode, only allow tapping your own button
      if (
        myPlayerId !== null &&
        myPlayerId !== undefined &&
        playerId !== myPlayerId
      )
        return;

      if (status === "READY") {
        // Early tap - disqualified
        setDisqualified((prev) => [...prev, playerId]);
        socketService.sendEvent("foul", { playerId });
        return;
      }

      if (status === "GO") {
        const reactionTime = Date.now() - startTime.current;
        setResults((prev) => [...prev, { playerId, time: reactionTime }]);
        socketService.sendEvent("hit", { playerId, time: reactionTime });

        // If everyone who is not disqualified has tapped, end game
        const remainingCount = players.length - disqualified.length;
        if (results.length + 1 >= remainingCount) {
          endGame([...results, { playerId, time: reactionTime }]);
        }
      }
    },
    [status, disqualified, results, players, myPlayerId],
  );

  // Timeout if people don't tap
  useEffect(() => {
    if (status === "GO") {
      const timeout = setTimeout(() => {
        if (!finishedRef.current) {
          endGame(results);
        }
      }, 3000);
      return () => clearTimeout(timeout);
    }
  }, [status, results]);

  const endGame = (finalResults: typeof results) => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    setStatus("FINISHED");

    // Score calculation: First gets 100, second 50, third 25, rest 0
    const scores = players.map((p) => {
      const rankIndex = finalResults.findIndex((r) => r.playerId === p.id);
      let score = 0;
      if (rankIndex === 0) score = 100;
      else if (rankIndex === 1) score = 50;
      else if (rankIndex === 2) score = 25;
      return { playerId: p.id, score };
    });

    setTimeout(() => onEnd(scores), 2000);
  };

  return (
    <div
      className={`h-full grid grid-cols-2 grid-rows-2 transition-colors duration-100 
      ${status === "GO" ? "bg-brand-green" : status === "READY" ? "bg-brand-accent" : "bg-brand-bg"}`}
    >
      {players.map((player) => (
        <button
          key={player.id}
          onClick={() => handleTap(player.id)}
          className={`
            relative flex flex-col items-center justify-center p-4 border border-white/10 overflow-hidden
            active:bg-white/20 focus:outline-none cursor-pointer group
            ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 grayscale-[0.5]" : ""}
          `}
          disabled={status === "FINISHED"}
        >
          <div className="absolute top-6 left-6 flex items-center gap-3 bg-black/30 backdrop-blur-md px-4 py-2 rounded-xl border border-white/10">
            <div
              className="w-3 h-3 rounded-full shadow-[0_0_10px_currentColor]"
              style={{ backgroundColor: player.color, color: player.color }}
            />
            <span className="font-black uppercase tracking-widest text-[10px] text-white/80">
              {player.name} {player.id === myPlayerId && "(YOU)"}
            </span>
          </div>

          <AnimatePresence mode="wait">
            {disqualified.includes(player.id) ? (
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                className="text-white font-black italic text-4xl drop-shadow-lg"
              >
                OVERHEAT!
              </motion.div>
            ) : results.some((r) => r.playerId === player.id) ? (
              <motion.div
                initial={{ y: 20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                className="flex flex-col items-center"
              >
                <span className="text-6xl font-black italic tracking-tighter">
                  {(results.find((r) => r.playerId === player.id)?.time || 0) /
                    1000}
                  s
                </span>
                <span className="text-xs uppercase font-black tracking-widest opacity-60">
                  Response Locked
                </span>
              </motion.div>
            ) : (
              <Zap
                className={`w-20 h-20 transition-all duration-300 ${status === "GO" ? "text-white opacity-100 scale-125" : "text-white/5 opacity-10"}`}
                strokeWidth={3}
              />
            )}
          </AnimatePresence>

          {/* Touch feedback */}
          <div className="absolute inset-0 bg-white/0 group-active:bg-white/5 transition-colors pointer-events-none" />
        </button>
      ))}

      {/* Center Overlay Instruction */}
      <div className="fixed inset-0 pointer-events-none flex items-center justify-center z-20">
        <AnimatePresence>
          {status === "WAIT" && (
            <motion.div
              exit={{ scale: 2, opacity: 0 }}
              className="bg-brand-card p-10 rounded-[2rem] border-4 border-brand-cyan shadow-2xl flex flex-col items-center gap-4"
            >
              <div className="w-12 h-12 bg-brand-cyan/20 rounded-full animate-ping absolute" />
              <h2 className="text-4xl font-black uppercase italic tracking-tighter relative">
                Stand By...
              </h2>
            </motion.div>
          )}
          {status === "READY" && (
            <motion.div
              initial={{ scale: 1.5, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              className="text-9xl font-black uppercase italic text-white drop-shadow-[0_0_30px_rgba(255,0,128,0.5)]"
            >
              STEADY
            </motion.div>
          )}
          {status === "GO" && (
            <motion.div
              initial={{ scale: 3, rotate: -10, opacity: 0 }}
              animate={{ scale: 1, rotate: 0, opacity: 1 }}
              className="text-[12rem] font-black uppercase italic text-white drop-shadow-[0_0_50px_rgba(0,242,255,0.8)]"
            >
              ZAP!
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
