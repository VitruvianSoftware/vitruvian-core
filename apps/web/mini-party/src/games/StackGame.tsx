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

// STACK! — a block slides back and forth; tap to drop it on the tower. Any
// part hanging over the edge is sliced off, so the blocks get narrower. Miss
// completely and your tower is done. Score is how many floors you stacked.

import { useRef, useState } from "react";
import { Player } from "../types";
import {
  GameScreen,
  PlayerPanels,
  useFrame,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";

export const sticker = (
  <>
    <rect x="22" y="84" width="76" height="22" rx="5" fill="#FF0080" />
    <rect x="30" y="60" width="64" height="22" rx="5" fill="#FFD700" />
    <rect x="34" y="36" width="52" height="22" rx="5" fill="#00F2FF" />
    <rect x="52" y="12" width="44" height="22" rx="5" fill="#4ECCA3" />
  </>
);

// Positions and widths are in percent of the board's width.
interface Floor {
  left: number;
  width: number;
}

const START_WIDTH = 60;
const VISIBLE_FLOORS = 9;
const COLORS = ["#FF0080", "#FFD700", "#00F2FF", "#4ECCA3", "#4D79FF"];

function Board({ player, round }: { player: Player; round: Round }) {
  const [tower, setTower] = useState<Floor[]>([
    { left: 20, width: START_WIDTH },
  ]);
  const [x, setX] = useState(0);
  const dir = useRef(1);
  const top = tower[tower.length - 1];
  const active = round.canPlay(player.id);
  // Speeds up as the tower grows.
  const speed = 45 + tower.length * 6;

  useFrame(active, (dt) => {
    setX((prev) => {
      let next = prev + dir.current * speed * dt;
      if (next + top.width > 100) {
        next = 100 - top.width;
        dir.current = -1;
      } else if (next < 0) {
        next = 0;
        dir.current = 1;
      }
      return next;
    });
  });

  const drop = () => {
    if (!active) return;
    const left = Math.max(x, top.left);
    const right = Math.min(x + top.width, top.left + top.width);
    const width = right - left;
    if (width <= 1) {
      round.finish(player.id);
      return;
    }
    setTower((t) => [...t, { left, width }]);
    round.addScore(player.id, 1);
    setX(0);
    dir.current = 1;
  };

  const shown = tower.slice(-VISIBLE_FLOORS);
  const offset = tower.length - shown.length;
  const floorHeight = 100 / (VISIBLE_FLOORS + 2);

  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        drop();
      }}
      className="absolute inset-0 cursor-pointer"
      aria-label="Drop block"
    >
      {shown.map((f, i) => (
        <div
          key={offset + i}
          className="absolute rounded-md border-2 border-brand-bg"
          style={{
            left: `${f.left}%`,
            width: `${f.width}%`,
            bottom: `${i * floorHeight}%`,
            height: `${floorHeight}%`,
            backgroundColor: COLORS[(offset + i) % COLORS.length],
          }}
        />
      ))}
      {active && (
        <div
          className="absolute rounded-md border-2 border-white shadow-[0_0_20px_#fff]"
          style={{
            left: `${x}%`,
            width: `${top.width}%`,
            bottom: `${shown.length * floorHeight}%`,
            height: `${floorHeight}%`,
            backgroundColor: COLORS[tower.length % COLORS.length],
          }}
        />
      )}
    </button>
  );
}

export default function StackGame(props: GameProps) {
  const round = useRound(props, { gameId: "stack", seconds: 30 });
  return (
    <GameScreen
      round={round}
      players={props.players}
      title="STACK!"
      howTo="Tap to drop the block on the tower"
      detail="Overhang gets sliced off · miss and you're out"
    >
      <PlayerPanels round={round} players={props.players} unit="floors">
        {(player) => <Board player={player} round={round} />}
      </PlayerPanels>
    </GameScreen>
  );
}
