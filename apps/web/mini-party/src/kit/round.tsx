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

// The game kit: everything a mini-game needs except its own idea.
//
//   useRound()      the round's clock, scores and who is finished, kept in
//                   step across devices in an online room.
//   <GameScreen>    the title bar, countdown and "how to play" intro.
//   <PlayerPanels>  one board per player on a shared screen, or just your own
//                   board (plus everyone's score) in an online room.
//
// A game built on the kit only writes a Board component for one player and
// calls round.addScore / round.setScore / round.finish from it.

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { motion, AnimatePresence } from "motion/react";
import { Player } from "../types";
import { socketService } from "../services/socketService";
import { seededRandom } from "./logic";

export interface GameProps {
  players: Player[];
  onEnd: (results: { playerId: number; score: number }[]) => void;
  myPlayerId?: number | null;
  /** Same on every device for this round; feed it to seededRandom. */
  seed?: number;
}

export type Phase = "intro" | "playing" | "over";

export interface Round {
  phase: Phase;
  /** Seconds left on the clock while playing. */
  timeLeft: number;
  scores: Record<number, number>;
  finished: Record<number, boolean>;
  /** The round's seed. Same for every player, on every device. */
  seed: number;
  /** A fresh random source from the round's seed, plus an optional salt. */
  random: (salt?: number) => () => number;
  /** True when this player's board should accept input right now. */
  canPlay: (playerId: number) => boolean;
  /** True when this device controls this player (always true on a shared screen). */
  isMine: (playerId: number) => boolean;
  setScore: (playerId: number, score: number) => void;
  addScore: (playerId: number, delta: number) => void;
  /** Lock in this player's score. The round ends when every player is finished. */
  finish: (playerId: number, finalScore?: number) => void;
}

interface RoundOptions {
  /** Names this game's network messages, so a late message from the previous round is ignored. */
  gameId: string;
  /** How long play lasts. */
  seconds: number;
  /** How long the intro card shows before play starts. */
  introMs?: number;
  /** Scores can't drop below this. */
  minScore?: number;
}

type ScoreMessage = {
  gameId: string;
  playerId: number;
  score: number;
  done: boolean;
};

export function useRound(props: GameProps, options: RoundOptions): Round {
  const { players, onEnd, myPlayerId } = props;
  const { gameId, seconds, introMs = 2500, minScore = 0 } = options;
  const seed = props.seed ?? 1;
  const remote = myPlayerId !== null && myPlayerId !== undefined;

  const [phase, setPhase] = useState<Phase>("intro");
  const [timeLeft, setTimeLeft] = useState(seconds);
  const [scores, setScores] = useState<Record<number, number>>(() =>
    Object.fromEntries(players.map((p) => [p.id, 0])),
  );
  const [finished, setFinished] = useState<Record<number, boolean>>({});

  // Refs mirror state so timers and network handlers never read stale values.
  const scoresRef = useRef(scores);
  const finishedRef = useRef(finished);
  const phaseRef = useRef<Phase>("intro");
  const endedRef = useRef(false);
  const onEndRef = useRef(onEnd);
  onEndRef.current = onEnd;

  const endRound = useCallback(() => {
    if (endedRef.current) return;
    endedRef.current = true;
    phaseRef.current = "over";
    setPhase("over");
    const results = players.map((p) => ({
      playerId: p.id,
      score: Math.max(0, Math.round(scoresRef.current[p.id] ?? 0)),
    }));
    window.setTimeout(() => onEndRef.current(results), 1800);
  }, [players]);

  const checkAllDone = useCallback(() => {
    if (players.every((p) => finishedRef.current[p.id])) endRound();
  }, [players, endRound]);

  // Apply a score to local state; optionally tell the other devices.
  const apply = useCallback(
    (playerId: number, score: number, done: boolean, broadcast: boolean) => {
      if (endedRef.current) return;
      if (finishedRef.current[playerId] && !done) return;
      const clamped = Math.max(minScore, score);
      scoresRef.current = { ...scoresRef.current, [playerId]: clamped };
      setScores(scoresRef.current);
      if (done && !finishedRef.current[playerId]) {
        finishedRef.current = { ...finishedRef.current, [playerId]: true };
        setFinished(finishedRef.current);
      }
      if (broadcast && remote) {
        const msg: ScoreMessage = { gameId, playerId, score: clamped, done };
        socketService.sendEvent("kit-score", msg);
      }
      if (done) checkAllDone();
    },
    [gameId, minScore, remote, checkAllDone],
  );

  // Other devices' scores.
  useEffect(() => {
    if (!remote) return;
    return socketService.onRemoteEvent(({ event, data }) => {
      if (event !== "kit-score") return;
      const msg = data as ScoreMessage;
      if (msg?.gameId !== gameId || msg.playerId === myPlayerId) return;
      if (!players.some((p) => p.id === msg.playerId)) return;
      apply(msg.playerId, Number(msg.score) || 0, !!msg.done, false);
    });
  }, [remote, gameId, myPlayerId, players, apply]);

  // Intro, then the clock.
  useEffect(() => {
    const start = window.setTimeout(() => {
      phaseRef.current = "playing";
      setPhase("playing");
    }, introMs);
    return () => window.clearTimeout(start);
  }, [introMs]);

  useEffect(() => {
    if (phase !== "playing") return;
    const startedAt = performance.now();
    const tick = window.setInterval(() => {
      const left = Math.max(
        0,
        seconds - (performance.now() - startedAt) / 1000,
      );
      setTimeLeft(left);
      if (left <= 0) {
        window.clearInterval(tick);
        endRound();
      }
    }, 100);
    return () => window.clearInterval(tick);
  }, [phase, seconds, endRound]);

  const isMine = useCallback(
    (playerId: number) => !remote || playerId === myPlayerId,
    [remote, myPlayerId],
  );

  const canPlay = useCallback(
    (playerId: number) =>
      phase === "playing" && !finished[playerId] && isMine(playerId),
    [phase, finished, isMine],
  );

  const setScore = useCallback(
    (playerId: number, score: number) => {
      if (phaseRef.current !== "playing" || !isMine(playerId)) return;
      apply(playerId, score, false, true);
    },
    [apply, isMine],
  );

  const addScore = useCallback(
    (playerId: number, delta: number) => {
      if (phaseRef.current !== "playing" || !isMine(playerId)) return;
      apply(playerId, (scoresRef.current[playerId] ?? 0) + delta, false, true);
    },
    [apply, isMine],
  );

  const finish = useCallback(
    (playerId: number, finalScore?: number) => {
      if (!isMine(playerId) || finishedRef.current[playerId]) return;
      apply(
        playerId,
        finalScore ?? scoresRef.current[playerId] ?? 0,
        true,
        true,
      );
    },
    [apply, isMine],
  );

  const random = useCallback(
    (salt = 0) => seededRandom((seed ^ Math.imul(salt + 1, 0x9e3779b1)) >>> 0),
    [seed],
  );

  return useMemo(
    () => ({
      phase,
      timeLeft,
      scores,
      finished,
      seed,
      random,
      canPlay,
      isMine,
      setScore,
      addScore,
      finish,
    }),
    [
      phase,
      timeLeft,
      scores,
      finished,
      seed,
      random,
      canPlay,
      isMine,
      setScore,
      addScore,
      finish,
    ],
  );
}

/**
 * Calls `step(dtSeconds)` every animation frame while `active` is true. The
 * frame time is capped so a backgrounded tab doesn't teleport things.
 */
export function useFrame(active: boolean, step: (dt: number) => void) {
  const stepRef = useRef(step);
  stepRef.current = step;
  useEffect(() => {
    if (!active) return;
    let raf = 0;
    let last = performance.now();
    const loop = (now: number) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      stepRef.current(dt);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [active]);
}

interface GameScreenProps {
  round: Round;
  players: Player[];
  title: string;
  /** One short line: what to do. Shown on the intro card and in the title bar. */
  howTo: string;
  /** Optional extra line on the intro card, e.g. scoring. */
  detail?: string;
  /** Hide the clock for games that end on their own. */
  showClock?: boolean;
  children: ReactNode;
}

export function GameScreen({
  round,
  players,
  title,
  howTo,
  detail,
  showClock = true,
  children,
}: GameScreenProps) {
  const urgent = round.phase === "playing" && round.timeLeft <= 5;
  return (
    <div className="h-full flex flex-col bg-brand-bg relative overflow-hidden select-none">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,_var(--color-brand-cyan)_0%,_transparent_70%)] opacity-5 pointer-events-none" />
      <header className="relative z-10 flex items-center justify-between gap-4 px-4 sm:px-6 py-3 border-b border-white/10 bg-brand-card/30">
        <div className="min-w-0">
          <h2 className="text-2xl sm:text-3xl font-black italic uppercase tracking-tighter leading-none">
            {title}
          </h2>
          <p className="text-[10px] sm:text-xs font-bold uppercase tracking-widest text-brand-cyan truncate mt-1">
            {howTo}
          </p>
        </div>
        {showClock && (
          <div
            className={`text-4xl font-black tabular-nums italic ${urgent ? "text-brand-accent animate-pulse" : "text-white"}`}
            aria-label="Time left"
          >
            {round.timeLeft.toFixed(round.timeLeft < 10 ? 1 : 0)}
          </div>
        )}
      </header>

      <div className="relative z-0 flex-1 min-h-0">{children}</div>

      <AnimatePresence>
        {round.phase === "intro" && (
          <motion.div
            key="intro"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-brand-bg/95 backdrop-blur-xl flex items-center justify-center p-8 text-center"
          >
            <div className="max-w-xl">
              <h2 className="text-6xl sm:text-7xl font-black italic uppercase tracking-tighter mb-4">
                {title}
              </h2>
              <p className="text-lg sm:text-xl font-bold text-brand-cyan uppercase tracking-widest">
                {howTo}
              </p>
              {detail && (
                <p className="text-xs sm:text-sm font-black uppercase tracking-[0.3em] text-white/40 mt-6">
                  {detail}
                </p>
              )}
            </div>
          </motion.div>
        )}
        {round.phase === "over" && (
          <motion.div
            key="over"
            initial={{ opacity: 0, scale: 1.1 }}
            animate={{ opacity: 1, scale: 1 }}
            className="fixed inset-0 z-50 bg-brand-bg/80 backdrop-blur-md flex items-center justify-center p-8"
          >
            <div className="flex flex-col items-center gap-6">
              <h2 className="text-6xl font-black italic uppercase tracking-tighter">
                Time!
              </h2>
              <div className="flex flex-wrap justify-center gap-4">
                {[...players]
                  .sort(
                    (a, b) =>
                      (round.scores[b.id] ?? 0) - (round.scores[a.id] ?? 0),
                  )
                  .map((p) => (
                    <div
                      key={p.id}
                      className="px-6 py-4 rounded-2xl bg-brand-card border-b-4 text-center min-w-[8rem]"
                      style={{ borderBottomColor: p.color }}
                    >
                      <div className="text-[10px] font-black uppercase tracking-widest opacity-50">
                        {p.name}
                      </div>
                      <div className="text-4xl font-black italic tabular-nums">
                        {Math.round(round.scores[p.id] ?? 0)}
                      </div>
                    </div>
                  ))}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

interface PlayerPanelsProps {
  round: Round;
  players: Player[];
  /** Renders one player's board. Only called for players this device controls. */
  children: (player: Player) => ReactNode;
  /** Label next to the score, e.g. "pts" or "floors". */
  unit?: string;
}

/**
 * Lays out one board per player. On a shared screen every player gets a
 * quarter (or half) of the screen. In an online room you get your own board
 * full size, with everyone's live score along the top.
 */
export function PlayerPanels({
  round,
  players,
  children,
  unit = "pts",
}: PlayerPanelsProps) {
  const mine = players.filter((p) => round.isMine(p.id));
  const others = players.filter((p) => !round.isMine(p.id));
  const grid =
    mine.length <= 1
      ? "grid-cols-1 grid-rows-1"
      : mine.length === 2
        ? "grid-cols-1 grid-rows-2 sm:grid-cols-2 sm:grid-rows-1"
        : "grid-cols-2 grid-rows-2";

  return (
    <div className="h-full flex flex-col">
      {others.length > 0 && (
        <div className="flex justify-center gap-2 p-2">
          {others.map((p) => (
            <div
              key={p.id}
              className="flex items-center gap-2 px-3 py-1 rounded-full bg-brand-card/60 border border-white/10"
            >
              <span
                className="w-2.5 h-2.5 rounded-full"
                style={{ backgroundColor: p.color }}
              />
              <span className="text-[10px] font-black uppercase tracking-widest opacity-60">
                {p.name}
              </span>
              <span className="text-sm font-black tabular-nums">
                {Math.round(round.scores[p.id] ?? 0)}
              </span>
              {round.finished[p.id] && (
                <span className="text-[9px] font-black text-brand-green uppercase">
                  done
                </span>
              )}
            </div>
          ))}
        </div>
      )}
      <div className={`flex-1 min-h-0 grid ${grid} gap-2 p-2`}>
        {mine.map((player) => (
          <section
            key={player.id}
            className="relative min-h-0 min-w-0 flex flex-col rounded-3xl border-2 bg-brand-card/40 overflow-hidden"
            style={{ borderColor: `${player.color}55` }}
          >
            <div className="flex items-center justify-between px-4 pt-3 pb-1 shrink-0">
              <div className="flex items-center gap-2">
                <span
                  className="w-3 h-3 rounded-full"
                  style={{ backgroundColor: player.color }}
                />
                <span className="text-[10px] font-black uppercase tracking-widest opacity-50">
                  {player.name}
                  {others.length > 0 && " (you)"}
                </span>
              </div>
              <div
                className="text-xl font-black italic tabular-nums"
                style={{ color: player.color }}
              >
                {Math.round(round.scores[player.id] ?? 0)}
                <span className="text-[10px] ml-1 opacity-60 not-italic uppercase">
                  {unit}
                </span>
              </div>
            </div>
            <ScaledBoard>{children(player)}</ScaledBoard>
            {round.finished[player.id] && round.phase === "playing" && (
              <div className="absolute inset-0 bg-brand-bg/70 backdrop-blur-sm flex items-center justify-center">
                <span className="text-4xl font-black italic uppercase text-brand-green">
                  Done!
                </span>
              </div>
            )}
          </section>
        ))}
      </div>
    </div>
  );
}

// Boards are laid out for a phone-sized panel. On a bigger panel (a laptop
// split two ways, a TV) the whole board is scaled up with CSS zoom so it fills
// the space instead of floating small in the middle. Never scales down.
const DESIGN_WIDTH = 380;
const DESIGN_HEIGHT = 440;
const MAX_ZOOM = 2.2;

function ScaledBoard({ children }: { children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState<{
    width: number;
    height: number;
    zoom: number;
  } | null>(null);
  useEffect(() => {
    const el = outer.current;
    if (!el) return;
    const measure = () => {
      const { width, height } = el.getBoundingClientRect();
      const fit = Math.min(width / DESIGN_WIDTH, height / DESIGN_HEIGHT);
      // Round so tiny resizes don't re-layout every frame.
      const zoom = Math.round(Math.min(MAX_ZOOM, Math.max(1, fit)) * 20) / 20;
      setBox({ width, height, zoom });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  // Pixel lengths on a zoomed element are multiplied by the zoom, so a box of
  // (panel size / zoom) px renders exactly the size of the panel.
  const style =
    box && box.zoom > 1
      ? {
          width: box.width / box.zoom,
          height: box.height / box.zoom,
          zoom: box.zoom,
        }
      : { width: "100%", height: "100%" };
  return (
    <div ref={outer} className="relative flex-1 min-h-0">
      <div className="absolute top-0 left-0" style={style}>
        {children}
      </div>
    </div>
  );
}

/** A big, chunky choice button for answer-picking games. */
export function ChoiceButton({
  onClick,
  disabled,
  children,
  tone = "default",
  className = "",
}: {
  onClick: () => void;
  disabled?: boolean;
  children: ReactNode;
  tone?: "default" | "good" | "bad";
  className?: string;
}) {
  const toneClass =
    tone === "good"
      ? "bg-brand-green/30 border-brand-green"
      : tone === "bad"
        ? "bg-brand-accent/30 border-brand-accent"
        : "bg-white/5 border-white/10 hover:bg-white/10";
  return (
    <button
      type="button"
      onPointerDown={(e) => {
        e.preventDefault();
        if (!disabled) onClick();
      }}
      disabled={disabled}
      className={`rounded-2xl border-2 font-black italic text-2xl sm:text-3xl transition-all active:scale-95 cursor-pointer disabled:cursor-default disabled:opacity-60 ${toneClass} ${className}`}
    >
      {children}
    </button>
  );
}
