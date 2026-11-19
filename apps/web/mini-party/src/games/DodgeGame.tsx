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
import { ChevronUp } from "lucide-react";
import { socketService } from "../services/socketService";

interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
}

export default function DodgeGame({ players, onEnd, myPlayerId }: GameProps) {
  const [lanes, setLanes] = useState<Record<number, 0 | 1>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const [obstacles, setObstacles] = useState<
    { id: number; lane: number; y: number }[]
  >([]);
  const [isStarted, setIsStarted] = useState(false);
  const [survivals, setSurvivals] = useState<Record<number, number>>(
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const finishedRef = useRef(false);
  const obsId = useRef(0);

  useEffect(() => {
    // Listen for remote events
    socketService.onRemoteEvent(({ event, data }) => {
      if (event === "lane") {
        setLanes((prev) => ({ ...prev, [data.playerId]: data.lane }));
      } else if (event === "obs") {
        setObstacles((prev) => [...prev, data.obstacle]);
      }
    });

    const start = setTimeout(() => setIsStarted(true), 2000);
    return () => clearTimeout(start);
  }, []);

  useEffect(() => {
    if (!isStarted || finishedRef.current) return;

    const tick = setInterval(() => {
      // Spawn obstacles (Host only)
      if (myPlayerId === 0 || myPlayerId === null || myPlayerId === undefined) {
        if (Math.random() > 0.9) {
          const newObs = {
            id: obsId.current++,
            lane: Math.random() > 0.5 ? 1 : 0,
            y: -20,
          };
          setObstacles((prev) => [...prev, newObs]);
          socketService.sendEvent("obs", { obstacle: newObs });
        }
      }

      // Move obstacles and check collision
      setObstacles((prev) => {
        const next = prev
          .map((o) => ({ ...o, y: o.y + 5 }))
          .filter((o) => o.y < 120);

        players.forEach((p) => {
          if (survivals[p.id] < 0) return;

          const hit = next.find(
            (o) => o.lane === lanes[p.id] && o.y > 70 && o.y < 90,
          );
          if (hit) {
            setSurvivals((s) => ({ ...s, [p.id]: -1 }));
          } else {
            setSurvivals((s) => ({ ...s, [p.id]: s[p.id] + 1 }));
          }
        });

        return next;
      });

      if (players.every((p) => survivals[p.id] < 0)) endGame();
    }, 100);

    const timer = setTimeout(() => endGame(), 10000); // 10s max

    return () => {
      clearInterval(tick);
      clearTimeout(timer);
    };
  }, [isStarted, lanes, survivals]);

  const switchLane = (playerId: number) => {
    if (!isStarted || finishedRef.current || survivals[playerId] < 0) return;

    // In remote mode, you can only switch your own lane
    if (
      myPlayerId !== null &&
      myPlayerId !== undefined &&
      playerId !== myPlayerId
    )
      return;

    const newLane = lanes[playerId] === 0 ? 1 : 0;
    setLanes((prev) => ({ ...prev, [playerId]: newLane }));
    socketService.sendEvent("lane", { playerId, lane: newLane });
  };

  const endGame = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    const finalScores = players.map((p) => ({
      playerId: p.id,
      score: Math.max(0, survivals[p.id]),
    }));
    setTimeout(() => onEnd(finalScores), 1000);
  };

  return (
    <div className="h-full grid grid-cols-2 grid-rows-2 p-2 gap-2 bg-brand-bg">
      {players.map((player) => (
        <button
          key={player.id}
          onClick={() => switchLane(player.id)}
          className="relative bg-brand-card/30 rounded-3xl border-2 border-white/5 overflow-hidden active:bg-white/5 cursor-pointer"
        >
          <div className="absolute top-4 left-4 z-20 flex items-center gap-2">
            <div
              className="w-2 h-2 rounded-full"
              style={{ backgroundColor: player.color }}
            />
            <span className="text-[8px] font-black uppercase opacity-20">
              {player.name} {player.id === myPlayerId && "(YOU)"}
            </span>
          </div>

          <div className="absolute inset-0 flex">
            <div className="flex-1 border-r border-white/5 relative">
              <div className="absolute inset-x-0 top-0 bottom-0 opacity-10 bg-[linear-gradient(transparent_0%,rgba(0,242,255,0.1)_100%)] bg-[size:100%_40px]" />
            </div>
            <div className="flex-1 relative">
              <div className="absolute inset-x-0 top-0 bottom-0 opacity-10 bg-[linear-gradient(transparent_0%,rgba(0,242,255,0.1)_100%)] bg-[size:100%_40px]" />
            </div>
          </div>

          {/* Player Sprite */}
          <motion.div
            animate={{ left: lanes[player.id] === 0 ? "25%" : "75%" }}
            className="absolute bottom-8 w-10 h-10 -translate-x-1/2 z-10"
          >
            <div
              className="w-full h-full rounded-lg shadow-lg flex items-center justify-center"
              style={{ backgroundColor: player.color }}
            >
              <ChevronUp className="text-white w-6 h-6" strokeWidth={4} />
            </div>
            <div className="absolute -bottom-4 left-1/2 -translate-x-1/2 w-8 h-1 bg-white/20 rounded-full blur-sm" />
          </motion.div>

          {/* Obstacles per player view */}
          {obstacles.map((o) => (
            <motion.div
              key={o.id}
              animate={{ top: `${o.y}%` }}
              className="absolute w-8 h-8 -translate-x-1/2 bg-brand-accent rounded-md border-2 border-white shadow-[0_0_15px_#FF0080]"
              style={{ left: o.lane === 0 ? "25%" : "75%" }}
            />
          ))}

          {survivals[player.id] < 0 && (
            <div className="absolute inset-0 bg-brand-accent/20 backdrop-blur-sm flex items-center justify-center z-30">
              <span className="text-4xl font-black italic uppercase text-white drop-shadow-2xl">
                CRASH
              </span>
            </div>
          )}
        </button>
      ))}

      {!isStarted && (
        <div className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex flex-col items-center justify-center p-8 text-center text-white">
          <h2 className="text-7xl font-black italic uppercase tracking-tighter mb-4">
            AVOID!
          </h2>
          <p className="text-xl font-bold text-brand-cyan uppercase tracking-widest">
            Tap to switch lanes!
          </p>
        </div>
      )}
    </div>
  );
}
