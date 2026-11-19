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
import { Search } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

const SYMBOLS = ["★", "⬥", "●", "▲", "◆", "✖", "✚", "⚛"];

export default function ScanGame({ players, onEnd, myPlayerId }: GameProps) {
  const [targetSymbol, setTargetSymbol] = useState("");
  const [isShowing, setIsShowing] = useState(false);
  const [isSelecting, setIsSelecting] = useState(false);
  const [playerResults, setPlayerResults] = useState<
    Record<number, boolean | null>
  >(Object.fromEntries(players.map((p) => [p.id, null])));
  const finishedRef = useRef(false);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "result") {
        setPlayerResults((prev) => ({
          ...prev,
          [data.playerId]: data.correct,
        }));
      } else if (event === "target") {
        setTargetSymbol(data.symbol);
      }
    });

    if (myPlayerId === 0 || myPlayerId === null || myPlayerId === undefined) {
      const symbol = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)];
      setTargetSymbol(symbol);
      socketService.sendEvent("target", { symbol });
    }

    setTimeout(() => {
      setIsShowing(true);
      setTimeout(() => {
        setIsShowing(false);
        setIsSelecting(true);
      }, 500); // Very fast!
    }, 2000);
  }, []);

  const handleSelect = (playerId: number, symbol: string) => {
    if (!isSelecting || finishedRef.current || playerResults[playerId] !== null)
      return;

    // In remote mode, you can only select for yourself
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    const isCorrect = symbol === targetSymbol;
    setPlayerResults((prev) => ({ ...prev, [playerId]: isCorrect }));
    socketService.sendEvent("result", { playerId, correct: isCorrect });

    if (
      Object.values({ ...playerResults, [playerId]: isCorrect }).every(
        (r) => r !== null,
      )
    ) {
      endGame({ ...playerResults, [playerId]: isCorrect });
    }
  };

  const endGame = (finalResults: Record<number, boolean | null>) => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    const scores = players.map((p) => ({
      playerId: p.id,
      score: finalResults[p.id] ? 100 : 0,
    }));
    setTimeout(() => onEnd(scores), 1500);
  };

  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden">
      <div className="h-1/2 flex items-center justify-center bg-black/50 border-b border-white/5 relative">
        <div className="absolute inset-0 opacity-10 bg-[linear-gradient(rgba(255,255,255,0.05)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.05)_1px,transparent_1px)] bg-[size:40px_40px]" />
        <div className="absolute top-0 left-0 right-0 h-[2px] bg-brand-cyan/20 animate-scan pointer-events-none" />

        <AnimatePresence mode="wait">
          {isShowing ? (
            <motion.div
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1.5, opacity: 1 }}
              exit={{ scale: 2, opacity: 0 }}
              className="text-9xl font-black text-brand-cyan drop-shadow-[0_0_20px_#00F2FF]"
            >
              {targetSymbol}
            </motion.div>
          ) : !isSelecting ? (
            <div className="flex flex-col items-center gap-4">
              <Search className="w-12 h-12 text-white/20 animate-pulse" />
              <span className="text-[10px] font-black uppercase tracking-[1em] text-white/20">
                Initializing Scan
              </span>
            </div>
          ) : (
            <div className="text-4xl font-black italic uppercase tracking-tighter text-white animate-pulse">
              Select the Target
            </div>
          )}
        </AnimatePresence>
      </div>

      <div className="flex-1 grid grid-cols-2 grid-rows-2 p-2 gap-2">
        {players.map((player) => (
          <div
            key={player.id}
            className="relative flex flex-col bg-brand-card/40 rounded-3xl border-2 border-white/5 p-4 overflow-hidden"
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
              className={`grid grid-cols-4 gap-1 mt-4 ${myPlayerId !== null && myPlayerId !== undefined && player.id !== myPlayerId ? "opacity-40 pointer-events-none" : ""}`}
            >
              {SYMBOLS.map((s, i) => (
                <button
                  key={i}
                  onClick={() => handleSelect(player.id, s)}
                  className={`
                                    h-12 flex items-center justify-center rounded-xl font-black text-xl transition-all cursor-pointer
                                    ${playerResults[player.id] !== null ? "opacity-20 pointer-events-none" : "bg-white/5 border border-white/10 hover:bg-brand-cyan hover:text-brand-bg active:scale-95"}
                                `}
                >
                  {s}
                </button>
              ))}
            </div>

            {playerResults[player.id] !== null && (
              <div
                className={`absolute inset-0 flex items-center justify-center backdrop-blur-md ${playerResults[player.id] ? "bg-brand-green/20" : "bg-brand-accent/20"}`}
              >
                <span className="text-4xl font-black italic">
                  {playerResults[player.id] ? "MATCH" : "ERROR"}
                </span>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
