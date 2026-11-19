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

import { motion } from "motion/react";
import { Player } from "../types";
import { Trophy, RotateCcw } from "lucide-react";

interface ScoreboardProps {
  players: Player[];
  onRestart: () => void;
}

export default function Scoreboard({ players, onRestart }: ScoreboardProps) {
  const sortedPlayers = [...players].sort(
    (a, b) => b.wins - a.wins || b.score - a.score,
  );
  const totalWinner = sortedPlayers[0];

  return (
    <div className="h-full flex flex-col items-center justify-center p-8 bg-brand-bg relative overflow-hidden">
      {/* Background glow */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[60%] h-[60%] bg-brand-cyan/5 blur-[150px] rounded-full pointer-events-none" />

      <motion.div
        initial={{ scale: 0.9, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        className="w-full max-w-4xl relative z-10"
      >
        <div className="flex justify-between items-center bg-brand-card/80 backdrop-blur-xl rounded-[2rem] p-8 mb-8 border-b-4 border-brand-accent border-2 border-white/5">
          <div className="flex items-center gap-6">
            <div className="w-14 h-14 bg-brand-accent rounded-xl flex items-center justify-center shadow-[0_0_15px_rgba(255,0,128,0.5)]">
              <Trophy className="text-white w-8 h-8 font-black" />
            </div>
            <h1 className="text-4xl font-black uppercase italic tracking-tighter">
              Leaderboard <span className="text-brand-cyan">Finals</span>
            </h1>
          </div>
          <div className="px-5 py-2 bg-brand-cyan/20 text-brand-cyan font-black rounded-full text-xs tracking-widest border border-brand-cyan/30">
            MATCH COMPLETE
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4 mb-10">
          {sortedPlayers.map((player, index) => (
            <motion.div
              key={player.id}
              initial={{ x: -30, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              transition={{ delay: index * 0.1 }}
              className={`
                flex items-center gap-6 p-5 rounded-2xl border-l-4 transition-all
                ${index === 0 ? "bg-white/10 scale-105 border-brand-gold" : "bg-brand-card/40 border-white/10"}
              `}
              style={{ borderLeftColor: player.color }}
            >
              <div
                className={`w-12 h-12 rounded-xl flex items-center justify-center font-black text-xl italic ${index === 0 ? "bg-brand-gold text-black" : "bg-white/10 text-white/40"}`}
              >
                {index + 1}
              </div>

              <div className="flex-grow">
                <div className="flex items-center justify-between mb-1">
                  <h3 className="text-2xl font-black uppercase italic">
                    {player.name}
                  </h3>
                  <div className="text-right">
                    <span className="text-3xl font-black italic text-white leading-none">
                      {player.wins}
                    </span>
                    <span className="text-[10px] block font-bold uppercase text-gray-500 tracking-widest">
                      Victory Points
                    </span>
                  </div>
                </div>
                <div className="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                  <motion.div
                    initial={{ width: 0 }}
                    animate={{
                      width: `${(player.score / Math.max(...players.map((p) => p.score), 1)) * 100}%`,
                    }}
                    className="h-full"
                    style={{ backgroundColor: player.color }}
                  />
                </div>
              </div>
            </motion.div>
          ))}
        </div>

        <div className="flex justify-between items-center bg-brand-card p-6 rounded-3xl border-2 border-white/5">
          <div className="flex flex-col">
            <span className="text-[10px] font-bold text-gray-500 uppercase tracking-[0.3em] mb-1">
              Grand Champion
            </span>
            <span className="text-3xl font-black italic uppercase text-brand-gold drop-shadow-[0_0_10px_rgba(255,215,0,0.3)]">
              {totalWinner.name}
            </span>
          </div>

          <button
            onClick={onRestart}
            className="flex items-center gap-3 px-10 py-5 bg-white text-brand-bg font-black text-lg hover:bg-brand-cyan transition-all uppercase tracking-widest rounded-2xl cursor-pointer active:scale-95 group shadow-xl"
            id="restart-button"
          >
            <RotateCcw className="w-6 h-6 group-hover:rotate-180 transition-transform duration-500" />
            Rematch
          </button>
        </div>
      </motion.div>
    </div>
  );
}
