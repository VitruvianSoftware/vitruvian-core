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

// SPELL! — tap shuffled letter tiles in order to build each word. The first
// two words show faint letter hints; after that you spell from the tiles alone.

import { useEffect, useMemo, useRef, useState, type PointerEvent } from "react";
import { motion } from "motion/react";
import { Player } from "../types";
import {
  GameScreen,
  PlayerPanels,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { shuffle } from "../kit/logic";

export const sticker = (
  <>
    <rect
      x="10"
      y="42"
      width="38"
      height="44"
      rx="10"
      fill="#FFD700"
      transform="rotate(-10 29 64)"
    />
    <rect x="41" y="24" width="38" height="44" rx="10" fill="#00F2FF" />
    <rect
      x="72"
      y="44"
      width="38"
      height="44"
      rx="10"
      fill="#FF0080"
      transform="rotate(10 91 66)"
    />
    <path
      d="M51 39 H69 M60 39 V55"
      stroke="#0F0C29"
      strokeWidth="6"
      strokeLinecap="round"
      fill="none"
    />
  </>
);

const WORDS = [
  "CAKE",
  "FROG",
  "MOON",
  "JUMP",
  "FISH",
  "BIRD",
  "GOLD",
  "DRUM",
  "KING",
  "DUCK",
  "WIND",
  "TREE",
  "BELL",
  "BOAT",
  "KITE",
  "SNOW",
  "LION",
  "CRAB",
  "BOOK",
  "MILK",
  "BIKE",
  "GIFT",
  "FLAG",
  "LOCK",
  "APPLE",
  "TIGER",
  "CLOCK",
  "CLOUD",
  "PIZZA",
  "ROBOT",
  "CROWN",
  "MAGIC",
  "TRAIN",
  "BEACH",
  "MUSIC",
  "FLAME",
  "STORM",
  "GHOST",
  "CANDY",
  "SHARK",
  "PLANT",
  "HOUSE",
  "WATER",
  "ZEBRA",
  "PANDA",
  "HONEY",
  "PLANET",
  "ROCKET",
  "CASTLE",
  "DRAGON",
  "BRIDGE",
  "JUNGLE",
  "ISLAND",
  "GUITAR",
  "SILVER",
  "SUNSET",
  "BUBBLE",
  "PIRATE",
  "COOKIE",
  "MONKEY",
];

interface Tile {
  id: number;
  ch: string;
}

interface Puzzle {
  word: string;
  tiles: Tile[];
}

function makePuzzles(rand: () => number): Puzzle[] {
  return shuffle(rand, WORDS).map((word) => {
    const tiles = shuffle(
      rand,
      word.split("").map((ch, id) => ({ id, ch })),
    );
    if (tiles.map((t) => t.ch).join("") === word) {
      const swap = tiles.findIndex((t) => t.ch !== tiles[0].ch);
      if (swap > 0) [tiles[0], tiles[swap]] = [tiles[swap], tiles[0]];
    }
    return { word, tiles };
  });
}

function Board({
  player,
  round,
  puzzles,
}: {
  player: Player;
  round: Round;
  puzzles: Puzzle[];
}) {
  const [wordIdx, setWordIdx] = useState(0);
  const [usedIds, setUsedIds] = useState<number[]>([]);
  const [badId, setBadId] = useState<number | null>(null);
  const [solved, setSolved] = useState(false);
  const badTimer = useRef<number | null>(null);
  const nextTimer = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (badTimer.current !== null) window.clearTimeout(badTimer.current);
      if (nextTimer.current !== null) window.clearTimeout(nextTimer.current);
    };
  }, []);

  const puzzle = puzzles[wordIdx % puzzles.length];
  const progress = usedIds.length;
  const showHint = wordIdx < 2;
  const active = round.canPlay(player.id) && !solved;

  const tapTile = (tile: Tile) => {
    if (!active || usedIds.includes(tile.id)) return;
    if (tile.ch === puzzle.word[progress]) {
      const nextUsed = [...usedIds, tile.id];
      setUsedIds(nextUsed);
      if (nextUsed.length === puzzle.word.length) {
        round.addScore(player.id, puzzle.word.length * 5);
        setSolved(true);
        nextTimer.current = window.setTimeout(() => {
          setWordIdx((w) => w + 1);
          setUsedIds([]);
          setSolved(false);
        }, 300);
      }
    } else {
      round.addScore(player.id, -2);
      setBadId(tile.id);
      if (badTimer.current !== null) window.clearTimeout(badTimer.current);
      badTimer.current = window.setTimeout(() => setBadId(null), 280);
    }
  };

  return (
    <div className="h-full flex flex-col items-center justify-between gap-3 p-3 min-h-0">
      <div className="flex items-center justify-between w-full max-w-xs text-[10px] font-black uppercase tracking-widest shrink-0">
        <span className="text-white/50">Word {wordIdx + 1}</span>
        {showHint && (
          <span className="px-2 py-0.5 rounded-full bg-brand-cyan/20 text-brand-cyan">
            Hint
          </span>
        )}
      </div>

      <div className="flex flex-wrap justify-center gap-1.5 shrink-0">
        {puzzle.word.split("").map((ch, i) => {
          const filled = i < progress;
          return (
            <div
              key={i}
              className={`w-9 h-10 sm:w-11 sm:h-12 rounded-xl border-2 flex items-center justify-center text-xl sm:text-2xl font-black italic uppercase transition-colors ${
                solved
                  ? "bg-brand-green/30 border-brand-green text-white"
                  : filled
                    ? "bg-brand-cyan/20 border-brand-cyan text-white"
                    : "bg-white/5 border-white/15"
              }`}
            >
              {filled ? (
                ch
              ) : showHint ? (
                <span className="text-white/20">{ch}</span>
              ) : (
                ""
              )}
            </div>
          );
        })}
      </div>

      <div className="flex flex-wrap justify-center gap-2 max-w-xs">
        {puzzle.tiles.map((tile) => {
          const used = usedIds.includes(tile.id);
          const isBad = badId === tile.id;
          return (
            <motion.button
              key={`${wordIdx}-${tile.id}`}
              type="button"
              animate={isBad ? { x: [0, -7, 7, -4, 4, 0] } : { x: 0 }}
              transition={{ duration: 0.25 }}
              onPointerDown={(e: PointerEvent<HTMLButtonElement>) => {
                e.preventDefault();
                tapTile(tile);
              }}
              disabled={!active || used}
              className={`w-11 h-11 sm:w-12 sm:h-12 rounded-xl border-2 text-xl sm:text-2xl font-black italic uppercase transition-all cursor-pointer disabled:cursor-default ${
                used
                  ? "opacity-15 scale-90 border-white/10 bg-white/5"
                  : isBad
                    ? "bg-brand-accent/40 border-brand-accent text-white"
                    : "bg-white/10 border-white/25 hover:bg-white/20 active:scale-90 text-white shadow-[0_4px_0_rgba(255,255,255,0.12)]"
              }`}
            >
              {tile.ch}
            </motion.button>
          );
        })}
      </div>
    </div>
  );
}

export default function SpellGame(props: GameProps) {
  const round = useRound(props, { gameId: "spell", seconds: 30 });
  const puzzles = useMemo(() => makePuzzles(round.random()), [round.random]);

  return (
    <GameScreen
      round={round}
      players={props.players}
      title="SPELL!"
      howTo="Tap letters in order"
      detail="+5 per letter · −2 wrong tap"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} puzzles={puzzles} />}
      </PlayerPanels>
    </GameScreen>
  );
}
