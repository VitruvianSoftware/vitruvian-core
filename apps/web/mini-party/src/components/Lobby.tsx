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

import { useState } from "react";
import { motion } from "motion/react";
import { Users, Play } from "lucide-react";
import { REMOTE_PLAY } from "../features";
import StickerField from "../art/StickerField";

interface LobbyProps {
  onStart: (playerCount: number) => void;
  onStartRemote: (playerName: string) => void;
  isJoining?: boolean;
}

export default function Lobby({
  onStart,
  onStartRemote,
  isJoining,
}: LobbyProps) {
  const [playerCount, setPlayerCount] = useState(2);
  const [mode, setMode] = useState<"LOCAL" | "ONLINE">(
    isJoining ? "ONLINE" : "LOCAL",
  );
  const [playerName, setPlayerName] = useState("");

  return (
    <div className="h-full flex flex-col items-center justify-center px-4 py-6 sm:p-8 bg-brand-bg relative overflow-hidden">
      {/* Every game's sticker, like the sheet in the box. */}
      <StickerField />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,var(--color-brand-bg)_30%,transparent_62%)]" />

      <div className="absolute top-[-10%] right-[-10%] w-[40%] h-[40%] bg-brand-accent/10 blur-[120px] rounded-full" />
      <div className="absolute bottom-[-10%] left-[-10%] w-[40%] h-[40%] bg-brand-cyan/10 blur-[120px] rounded-full" />

      <motion.div
        initial={{ y: -50, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="text-center mb-6 sm:mb-10 relative"
      >
        <div className="flex items-center justify-center gap-3 sm:gap-6 mb-3 sm:mb-4">
          <div className="shrink-0 w-10 h-10 sm:w-16 sm:h-16 bg-brand-accent rounded-xl sm:rounded-2xl flex items-center justify-center shadow-[0_0_20px_rgba(255,0,128,0.5)]">
            <span className="text-2xl sm:text-4xl font-black italic">M</span>
          </div>
          <h1 className="text-4xl sm:text-6xl lg:text-8xl font-black italic tracking-tighter uppercase">
            Mini Party <span className="text-brand-cyan">Turbo</span>
          </h1>
        </div>
        <p className="text-xs sm:text-xl font-bold text-gray-400 uppercase tracking-[0.25em] sm:tracking-[0.4em]">
          Reflex • Speed • Victory
        </p>
      </motion.div>

      <div className="flex flex-col items-center gap-5 sm:gap-8 w-full max-w-2xl relative">
        {!isJoining && REMOTE_PLAY && (
          <div className="flex bg-white/5 p-1.5 rounded-2xl border border-white/10 w-full">
            <button
              onClick={() => setMode("LOCAL")}
              className={`flex-1 py-3 text-xs sm:text-base font-black uppercase tracking-widest rounded-xl transition-all ${mode === "LOCAL" ? "bg-white text-brand-bg" : "text-white/40 hover:text-white"}`}
            >
              Local Play
            </button>
            <button
              onClick={() => setMode("ONLINE")}
              className={`flex-1 py-3 text-xs sm:text-base font-black uppercase tracking-widest rounded-xl transition-all ${mode === "ONLINE" ? "bg-brand-cyan text-brand-bg shadow-[0_0_15px_#00F2FF]" : "text-white/40 hover:text-white"}`}
            >
              Remote Battle
            </button>
          </div>
        )}

        <p
          id="mode-hint"
          className="-mt-4 text-center text-sm font-bold text-white/60"
        >
          {mode === "LOCAL"
            ? "Everyone plays on this screen. Each player gets a corner to tap."
            : isJoining
              ? "You've been invited to a room. Pick a name to join."
              : "Everyone plays on their own phone or computer. Start a room, then share the link."}
        </p>

        {mode === "LOCAL" ? (
          <div className="w-full bg-brand-card/50 backdrop-blur-xl border-2 border-white/10 rounded-[2rem] sm:rounded-[2.5rem] p-5 sm:p-10">
            <label className="block text-center text-[10px] font-black uppercase tracking-[0.3em] text-brand-cyan mb-4 sm:mb-8">
              Select Challengers
            </label>
            <div className="grid grid-cols-3 gap-3 sm:gap-6">
              {[2, 3, 4].map((num) => (
                <button
                  key={num}
                  onClick={() => setPlayerCount(num)}
                  className={`
                    relative py-6 sm:py-10 rounded-2xl text-4xl sm:text-5xl font-black transition-all border-4 flex flex-col items-center justify-center gap-2 group
                    ${
                      playerCount === num
                        ? "bg-brand-accent text-white border-white scale-105 shadow-[0_0_30px_rgba(255,0,128,0.3)]"
                        : "bg-white/5 text-white/40 border-white/10 hover:border-white/30"
                    }
                  `}
                  id={`players-${num}`}
                >
                  {num}
                  <Users
                    className={`w-5 h-5 ${playerCount === num ? "text-white/60" : "opacity-0 transition-opacity group-hover:opacity-20"}`}
                  />
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="w-full bg-brand-card/50 backdrop-blur-xl border-2 border-white/10 rounded-[2rem] sm:rounded-[2.5rem] p-5 sm:p-10">
            <label className="block text-center text-[10px] font-black uppercase tracking-[0.3em] text-brand-cyan mb-4 sm:mb-8">
              Pilot Identity
            </label>
            <input
              type="text"
              value={playerName}
              onChange={(e) => setPlayerName(e.target.value.substring(0, 10))}
              placeholder="ENTER CALLSIGN..."
              className="w-full bg-black/40 border-2 border-white/10 rounded-2xl p-4 sm:p-6 text-xl sm:text-2xl font-black italic uppercase placeholder:opacity-20 focus:border-brand-cyan outline-none transition-all text-center"
            />
          </div>
        )}

        <button
          onClick={() =>
            mode === "LOCAL" ? onStart(playerCount) : onStartRemote(playerName)
          }
          disabled={mode === "ONLINE" && !playerName.trim()}
          className="group relative w-full py-5 sm:py-8 bg-white text-brand-bg font-black text-xl sm:text-3xl uppercase tracking-widest rounded-3xl overflow-hidden transition-all hover:scale-[1.02] active:scale-95 cursor-pointer shadow-2xl disabled:opacity-50 disabled:scale-100 disabled:cursor-not-allowed"
          id="start-match"
        >
          <span className="relative z-10 flex items-center justify-center gap-4">
            {mode === "LOCAL"
              ? "Launch Local Engine"
              : isJoining
                ? "Join Battle"
                : "Ignite Remote Room"}{" "}
            <Play className="fill-current w-6 h-6 sm:w-8 sm:h-8" />
          </span>
          <motion.div
            className={`absolute inset-0 ${mode === "ONLINE" ? "bg-brand-cyan/20" : "bg-brand-accent/20"}`}
            animate={{ x: ["-100%", "100%"] }}
            transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
          />
        </button>
      </div>

      <div className="absolute bottom-10 hidden sm:flex gap-8 items-center opacity-40 grayscale">
        <div className="flex flex-col items-end font-mono text-[10px]">
          <span>SYSTEM STATUS</span>
          <span className="text-brand-green font-bold">READY_TO_BOOT</span>
        </div>
        <div className="w-12 h-[2px] bg-white/20" />
        <div className="flex flex-col font-mono text-[10px]">
          <span>BUILD_REV</span>
          <span>AIS-TURBO-1.0</span>
        </div>
      </div>
    </div>
  );
}
