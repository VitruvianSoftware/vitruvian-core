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

// FLIP! — tap the D-pad button pointing opposite to the arrow shown, except
// every 5th prompt turns gold and means tap the same direction instead.

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp } from "lucide-react";
import { Player } from "../types";
import {
  ChoiceButton,
  GameScreen,
  PlayerPanels,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { randInt } from "../kit/logic";

export const sticker = (
  <>
    <polygon points="36,14 60,46 46,46 46,104 26,104 26,46 12,46" fill="#00F2FF" />
    <polygon points="84,106 108,74 94,74 94,16 74,16 74,74 60,74" fill="#FFD700" />
  </>
);

interface Prompt {
  dir: number; // 0=UP, 1=RIGHT, 2=DOWN, 3=LEFT
  gold: boolean;
}

const DIR_ICONS = [ArrowUp, ArrowRight, ArrowDown, ArrowLeft] as const;
const DIR_LABELS = ["Up", "Right", "Down", "Left"] as const;

function makePrompts(rand: () => number, count: number): Prompt[] {
  return Array.from({ length: count }, (_, i) => ({
    dir: randInt(rand, 0, 3),
    gold: (i + 1) % 5 === 0,
  }));
}

function Board({
  player,
  round,
  prompts,
}: {
  player: Player;
  round: Round;
  prompts: Prompt[];
}) {
  const [index, setIndex] = useState(0);
  const [streak, setStreak] = useState(0);
  const [flash, setFlash] = useState<{ dir: number; ok: boolean; pts: number } | null>(
    null,
  );
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const prompt = prompts[index % prompts.length];
  const expected = prompt.gold ? prompt.dir : (prompt.dir + 2) % 4;
  const active = round.canPlay(player.id) && !flash;
  const PromptIcon = DIR_ICONS[prompt.dir];

  const tap = (dir: number) => {
    if (!active) return;
    if (dir === expected) {
      const pts = 5 + Math.min(5, streak);
      round.addScore(player.id, pts);
      setStreak((s) => s + 1);
      setFlash({ dir, ok: true, pts });
      timerRef.current = window.setTimeout(() => {
        setFlash(null);
        setIndex((i) => i + 1);
      }, 150);
    } else {
      round.addScore(player.id, -5);
      setStreak(0);
      setFlash({ dir, ok: false, pts: -5 });
      timerRef.current = window.setTimeout(() => {
        setFlash(null);
        setIndex((i) => i + 1);
      }, 340);
    }
  };

  const renderBtn = (dir: number) => {
    const Icon = DIR_ICONS[dir];
    return (
      <ChoiceButton
        onClick={() => tap(dir)}
        disabled={!active}
        tone={flash?.dir === dir ? (flash.ok ? "good" : "bad") : "default"}
        className="py-2.5 sm:py-3 flex items-center justify-center"
      >
        <Icon className="w-7 h-7 sm:w-8 sm:h-8 stroke-[3]" aria-label={DIR_LABELS[dir]} />
      </ChoiceButton>
    );
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-2 p-2.5 sm:p-4 min-h-0">
      <div className="w-full flex items-center justify-between text-[10px] sm:text-xs font-black uppercase tracking-widest shrink-0">
        <span className="text-brand-gold">STREAK ×{streak}</span>
        {flash && (
          <span className={flash.ok ? "text-brand-green" : "text-[#FF4D4D]"}>
            {flash.ok ? `+${flash.pts}` : "−5"}
          </span>
        )}
      </div>

      <motion.div
        key={index}
        initial={{ scale: 0.85, opacity: 0.7 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.12 }}
        className={`flex flex-col items-center justify-center px-6 py-2.5 sm:py-3 rounded-2xl border-2 shrink-0 ${
          prompt.gold
            ? "bg-brand-gold/25 border-brand-gold shadow-[0_0_24px_#FFD70066]"
            : "bg-brand-bg/90 border-white/15"
        }`}
      >
        <PromptIcon
          className={`w-12 h-12 sm:w-16 sm:h-16 stroke-[3] ${
            prompt.gold ? "text-brand-gold" : "text-brand-cyan"
          }`}
        />
        <span
          className={`text-[11px] sm:text-xs font-black italic uppercase tracking-widest mt-0.5 ${
            prompt.gold ? "text-brand-gold" : "text-white/60"
          }`}
        >
          {prompt.gold ? "GOLD · SAME!" : "OPPOSITE"}
        </span>
      </motion.div>

      <div className="grid grid-cols-3 gap-2 w-full max-w-[230px] shrink-0">
        <div />
        {renderBtn(0)}
        <div />
        {renderBtn(3)}
        {renderBtn(2)}
        {renderBtn(1)}
      </div>
    </div>
  );
}

export default function OppositeGame(props: GameProps) {
  const round = useRound(props, { gameId: "opposite", seconds: 25 });
  const prompts = useMemo(() => makePrompts(round.random(), 120), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="FLIP!"
      howTo="Tap the OPPOSITE direction"
      detail="Every 5th arrow is GOLD = SAME direction! · +5 (+streak up to +5) · −5 wrong"
    >
      <PlayerPanels round={round} players={props.players} unit="pts">
        {(player) => <Board player={player} round={round} prompts={prompts} />}
      </PlayerPanels>
    </GameScreen>
  );
}
