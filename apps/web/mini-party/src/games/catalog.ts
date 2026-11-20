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

// Every mini-game in one list. A match plays ROUNDS_PER_MATCH of these, picked
// at random. Games built on the kit (src/kit) also export their sticker art.

import type { ComponentType, ReactNode } from "react";
import type { GameProps } from "../kit/round";
import ReactionGame from "./ReactionGame";
import MashGame from "./MashGame";
import PatternGame from "./PatternGame";
import StopGame from "./StopGame";
import CountGame from "./CountGame";
import TargetGame from "./TargetGame";
import TugGame from "./TugGame";
import BalanceGame from "./BalanceGame";
import MatchGame from "./MatchGame";
import FuelGame from "./FuelGame";
import ScanGame from "./ScanGame";
import DodgeGame from "./DodgeGame";
import SmashGame from "./SmashGame";
import MathGame, { sticker as mathSticker } from "./MathGame";
import StackGame, { sticker as stackSticker } from "./StackGame";
import JumpGame, { sticker as jumpSticker } from "./JumpGame";
import LockGame, { sticker as lockSticker } from "./LockGame";
import OrderGame, { sticker as orderSticker } from "./OrderGame";
import MemoryGame, { sticker as memorySticker } from "./MemoryGame";
import SortGame, { sticker as sortSticker } from "./SortGame";
import RhythmGame, { sticker as rhythmSticker } from "./RhythmGame";
import MoreGame, { sticker as moreSticker } from "./MoreGame";
import WheelGame, { sticker as wheelSticker } from "./WheelGame";
import CatchGame, { sticker as catchSticker } from "./CatchGame";
import MazeGame, { sticker as mazeSticker } from "./MazeGame";
import LightsGame, { sticker as lightsSticker } from "./LightsGame";
import SpellGame, { sticker as spellSticker } from "./SpellGame";
import CupsGame, { sticker as cupsSticker } from "./CupsGame";
import CopyGame, { sticker as copySticker } from "./CopyGame";
import BalloonGame, { sticker as balloonSticker } from "./BalloonGame";
import HiLoGame, { sticker as hiloSticker } from "./HiLoGame";
import SnapGame, { sticker as snapSticker } from "./SnapGame";
import HoopGame, { sticker as hoopSticker } from "./HoopGame";
import GreenGame, { sticker as greenSticker } from "./GreenGame";
import WiresGame, { sticker as wiresSticker } from "./WiresGame";
import TrackGame, { sticker as trackSticker } from "./TrackGame";
import SafeGame, { sticker as safeSticker } from "./SafeGame";
import DiceGame, { sticker as diceSticker } from "./DiceGame";
import ShadowGame, { sticker as shadowSticker } from "./ShadowGame";
import TurnGame, { sticker as turnSticker } from "./TurnGame";
import OppositeGame, { sticker as oppositeSticker } from "./OppositeGame";
import GearGame, { sticker as gearSticker } from "./GearGame";

export interface MiniGame {
  id: string;
  name: string;
  component: ComponentType<GameProps>;
}

export const MINI_GAMES: MiniGame[] = [
  { id: "reaction", name: "ZAP!", component: ReactionGame },
  { id: "mash", name: "BOOST!", component: MashGame },
  { id: "pattern", name: "ECHO!", component: PatternGame },
  { id: "stop", name: "PINPOINT!", component: StopGame },
  { id: "count", name: "GLANCE!", component: CountGame },
  { id: "target", name: "SNIPE!", component: TargetGame },
  { id: "tug", name: "TUG!", component: TugGame },
  { id: "balance", name: "STABLE!", component: BalanceGame },
  { id: "match", name: "COLOR!", component: MatchGame },
  { id: "fuel", name: "PUMP!", component: FuelGame },
  { id: "scan", name: "SEARCH!", component: ScanGame },
  { id: "dodge", name: "AVOID!", component: DodgeGame },
  { id: "smash", name: "SMASH!", component: SmashGame },
  { id: "math", name: "SUM!", component: MathGame },
  { id: "stack", name: "STACK!", component: StackGame },
  { id: "jump", name: "HOP!", component: JumpGame },
  { id: "lock", name: "CRACK!", component: LockGame },
  { id: "order", name: "1-2-3!", component: OrderGame },
  { id: "memory", name: "PAIRS!", component: MemoryGame },
  { id: "sort", name: "SORT!", component: SortGame },
  { id: "rhythm", name: "BEAT!", component: RhythmGame },
  { id: "more", name: "MORE!", component: MoreGame },
  { id: "wheel", name: "WHEEL!", component: WheelGame },
  { id: "catch", name: "CATCH!", component: CatchGame },
  { id: "maze", name: "MAZE!", component: MazeGame },
  { id: "lights", name: "DARK!", component: LightsGame },
  { id: "spell", name: "SPELL!", component: SpellGame },
  { id: "cups", name: "CUPS!", component: CupsGame },
  { id: "copy", name: "COPY!", component: CopyGame },
  { id: "balloon", name: "PUFF!", component: BalloonGame },
  { id: "hilo", name: "HI-LO!", component: HiLoGame },
  { id: "snap", name: "SNAP!", component: SnapGame },
  { id: "hoop", name: "HOOP!", component: HoopGame },
  { id: "green", name: "GREEN!", component: GreenGame },
  { id: "wires", name: "DEFUSE!", component: WiresGame },
  { id: "track", name: "TRACK!", component: TrackGame },
  { id: "safe", name: "SAFE!", component: SafeGame },
  { id: "dice", name: "PUSH!", component: DiceGame },
  { id: "shadow", name: "SHADOW!", component: ShadowGame },
  { id: "turn", name: "TURN!", component: TurnGame },
  { id: "opposite", name: "FLIP!", component: OppositeGame },
  { id: "gear", name: "GEARS!", component: GearGame },
];

// Sticker art for the kit games (the original games' art lives in art/Sticker.tsx).
export const GAME_STICKERS: Record<string, ReactNode> = {
  math: mathSticker,
  stack: stackSticker,
  jump: jumpSticker,
  lock: lockSticker,
  order: orderSticker,
  memory: memorySticker,
  sort: sortSticker,
  rhythm: rhythmSticker,
  more: moreSticker,
  wheel: wheelSticker,
  catch: catchSticker,
  maze: mazeSticker,
  lights: lightsSticker,
  spell: spellSticker,
  cups: cupsSticker,
  copy: copySticker,
  balloon: balloonSticker,
  hilo: hiloSticker,
  snap: snapSticker,
  hoop: hoopSticker,
  green: greenSticker,
  wires: wiresSticker,
  track: trackSticker,
  safe: safeSticker,
  dice: diceSticker,
  shadow: shadowSticker,
  turn: turnSticker,
  opposite: oppositeSticker,
  gear: gearSticker,
};
