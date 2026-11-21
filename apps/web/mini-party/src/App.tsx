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

import { useState, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "motion/react";
import { GameState, Player, PLAYER_COLORS } from "./types";
import { createInitialPlayers } from "./constants";
import Lobby from "./components/Lobby";
import { Sticker } from "./art/Sticker";
import Scoreboard from "./components/Scoreboard";
import { MINI_GAMES } from "./games/catalog";
import { nextGameIndex, roundSeed, ROUNDS_PER_MATCH } from "./kit/logic";
import {
  Trophy,
  ChevronRight,
  Share2,
  Users,
  Radio,
  Globe,
  WifiOff,
} from "lucide-react";
import { socketService } from "./services/socketService";
import { REMOTE_PLAY } from "./features";
import { roomFromSearch } from "./room";
import { analytics } from "./analytics";

export default function App() {
  const [gameState, setGameState] = useState<GameState>("LOBBY");
  // Online only: false while this device's connection to the rooms server is
  // down. socket.io keeps retrying and the seat is held, so this is a pause.
  const [online, setOnline] = useState(true);
  const [players, setPlayers] = useState<Player[]>([]);
  const [currentGameIndex, setCurrentGameIndex] = useState(0);
  const [lastGameWinners, setLastGameWinners] = useState<number[]>([]);
  // A share link's room, read now so the lobby opens on online play.
  const [roomId, setRoomId] = useState<string | null>(() =>
    roomFromSearch(window.location.search, REMOTE_PLAY),
  );
  const [myPlayerId, setMyPlayerId] = useState<number | null>(null);
  // The games played so far this match, in order. Every device in a room
  // builds the same list from the host's game-started messages.
  const [played, setPlayed] = useState<number[]>([]);
  const playedRef = useRef<number[]>([]);

  const beginRound = (gameIndex: number) => {
    playedRef.current = [...playedRef.current, gameIndex];
    setPlayed(playedRef.current);
    setCurrentGameIndex(gameIndex);
    setGameState("GAME_START");
  };

  // ?game=<id> plays only that game, for trying one out.
  const onlyGame = MINI_GAMES.findIndex(
    (g) => g.id === new URLSearchParams(window.location.search).get("game"),
  );
  const pickNextGame = () =>
    onlyGame >= 0
      ? onlyGame
      : nextGameIndex(Math.random, MINI_GAMES.length, playedRef.current);

  // Picks the next game and reports it. Only the device that decides calls
  // this (see analytics.ts), so each round is counted once.
  const chooseNextGame = (mode: "local" | "online") => {
    const next = pickNextGame();
    analytics.gameStarted(
      mode,
      MINI_GAMES[next].id,
      playedRef.current.length + 1,
    );
    return next;
  };

  const startGame = (playerCount: number) => {
    setPlayers(createInitialPlayers(playerCount));
    playedRef.current = [];
    analytics.matchStarted("local", playerCount);
    beginRound(chooseNextGame("local"));
  };

  const startRemoteGame = (playerName: string) => {
    const socket = socketService.connect();
    const id = roomId || Math.random().toString(36).substring(7).toUpperCase();
    setRoomId(id);

    // Update URL without refreshing
    const newUrl = `${window.location.origin}${window.location.pathname}?room=${id}`;
    window.history.replaceState({ path: newUrl }, "", newUrl);

    socketService.joinRoom(id, playerName, PLAYER_COLORS[0]); // Host or Joiner
    socketService.onConnectionChange(setOnline);

    socketService.onRoomUpdate(({ players: remotePlayers }) => {
      setPlayers(remotePlayers);
      // Find my player ID
      const me = remotePlayers.find(
        (p: any) => p.socketId === socketService.getSocketId(),
      );
      if (me) setMyPlayerId(me.id);
    });

    socketService.onGameStarted(({ gameIndex }) => {
      if (!Number.isInteger(gameIndex) || !MINI_GAMES[gameIndex]) return;
      beginRound(gameIndex);
    });

    // The host moves everyone from the title card into the game, and from the
    // last round to the final standings.
    socketService.onRemoteEvent(({ event }) => {
      if (event === "enter-arena") setGameState("PLAYING");
      if (event === "match-over") setGameState("SCOREBOARD");
    });
  };

  // The host's "Ignite Session" in the lobby: pick the first game.
  const startRemoteMatch = () => {
    playedRef.current = [];
    setPlayed([]);
    analytics.matchStarted("online", players.length);
    socketService.startGame(chooseNextGame("online"));
  };

  // "Enter Arena" on the title card.
  const enterArena = () => {
    if (roomId) socketService.sendEvent("enter-arena", {});
    setGameState("PLAYING");
  };

  const copyLink = () => {
    if (roomId) {
      navigator.clipboard.writeText(window.location.href);
      // Minimal feedback
    }
  };

  const handleGameEnd = (results: { playerId: number; score: number }[]) => {
    const sortedResults = [...results].sort((a, b) => b.score - a.score);
    const maxScore = sortedResults.length > 0 ? sortedResults[0].score : 0;
    const winners = sortedResults
      .filter((r) => r.score === maxScore && maxScore > 0)
      .map((r) => r.playerId);

    setLastGameWinners(winners);

    if (!roomId || myPlayerId === 0) {
      analytics.gameFinished(
        roomId ? "online" : "local",
        MINI_GAMES[currentGameIndex]?.id ?? "unknown",
        playedRef.current.length,
        maxScore,
      );
    }

    setPlayers((prev) =>
      prev.map((p) => {
        const isWinner = winners.includes(p.id);
        const playerResult = results.find((r) => r.playerId === p.id);
        return {
          ...p,
          wins: isWinner ? p.wins + 1 : p.wins,
          score: p.score + (playerResult?.score || 0),
        };
      }),
    );

    setGameState("GAME_END");
  };

  const nextPhase = () => {
    const mode = roomId ? "online" : "local";
    if (playedRef.current.length < ROUNDS_PER_MATCH) {
      const next = chooseNextGame(mode);
      if (roomId) {
        socketService.startGame(next);
      } else {
        beginRound(next);
      }
    } else {
      if (roomId) socketService.sendEvent("match-over", {});
      analytics.matchFinished(mode, players.length, playedRef.current.length);
      setGameState("SCOREBOARD");
    }
  };

  const resetToLobby = () => {
    setGameState("LOBBY");
    setPlayers([]);
    setCurrentGameIndex(0);
    playedRef.current = [];
    setPlayed([]);
    setRoomId(null);
    setMyPlayerId(null);
    window.history.replaceState({}, "", window.location.pathname);
  };

  const renderGame = () => {
    const game = MINI_GAMES[currentGameIndex];
    if (!game) return <div>Unknown Game</div>;
    const Game = game.component;
    // Same seed on every device in the room: room code + round number.
    const seed = roundSeed(roomId, played.length, currentGameIndex);
    return (
      <Game
        key={`${played.length}-${game.id}`}
        players={players}
        onEnd={handleGameEnd}
        myPlayerId={myPlayerId}
        seed={seed}
      />
    );
  };

  return (
    <div className="min-h-screen bg-brand-bg text-white font-sans overflow-hidden selection:bg-brand-accent">
      <AnimatePresence mode="wait">
        {gameState === "LOBBY" && (
          <motion.div
            key="lobby"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="h-screen"
          >
            <Lobby
              onStart={startGame}
              onStartRemote={startRemoteGame}
              isJoining={!!roomId}
            />

            {roomId && players.length > 0 && (
              <div className="fixed top-0 left-0 right-0 p-8 z-50 flex items-center justify-center pointer-events-none">
                <div className="bg-brand-card/90 backdrop-blur-xl border border-white/10 rounded-[2rem] p-6 shadow-2xl flex items-center gap-12 pointer-events-auto">
                  <div className="flex items-center gap-4">
                    <Radio className="text-brand-cyan animate-pulse" />
                    <div className="flex flex-col">
                      <span className="text-[10px] font-black uppercase tracking-widest text-brand-cyan">
                        Command Center
                      </span>
                      <span className="text-xl font-mono font-black">
                        {roomId}
                      </span>
                    </div>
                  </div>

                  <div className="flex gap-2">
                    {players.map((p) => (
                      <div
                        key={p.id}
                        className={`w-10 h-10 rounded-full border-2 border-white/20 shadow-lg transition-opacity ${
                          p.connected === false
                            ? "opacity-30 animate-pulse"
                            : ""
                        }`}
                        style={{ backgroundColor: p.color }}
                        title={
                          p.connected === false
                            ? `${p.name} (reconnecting)`
                            : p.name
                        }
                      />
                    ))}
                    {[...Array(4 - players.length)].map((_, i) => (
                      <div
                        key={i}
                        className="w-10 h-10 rounded-full border-2 border-white/5 bg-white/5 flex items-center justify-center"
                      >
                        <Users className="w-4 h-4 opacity-20" />
                      </div>
                    ))}
                  </div>

                  <div className="flex gap-3">
                    <button
                      onClick={copyLink}
                      className="p-4 bg-white/5 hover:bg-white/10 rounded-2xl border border-white/10 transition-all active:scale-95 group cursor-pointer"
                    >
                      <Share2 className="w-5 h-5 group-hover:text-brand-cyan" />
                    </button>
                    {players.length >= 2 && myPlayerId === 0 && (
                      <button
                        onClick={startRemoteMatch}
                        className="px-8 py-4 bg-brand-cyan text-brand-bg font-black uppercase tracking-widest rounded-2xl shadow-[0_0_20px_#00F2FF] hover:scale-105 transition-all cursor-pointer active:scale-95"
                      >
                        Ignite Session
                      </button>
                    )}
                  </div>
                </div>
              </div>
            )}
          </motion.div>
        )}

        {gameState === "GAME_START" && (
          <motion.div
            key="game-start"
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 1.2 }}
            className="h-screen flex flex-col items-center justify-center bg-brand-bg relative overflow-hidden"
          >
            {/* The round's sticker, tiled faintly behind it. */}
            <div
              className="absolute inset-[-10%] grid grid-cols-6 gap-[6vmin] p-[4vmin] opacity-[0.07] pointer-events-none rotate-[-8deg]"
              aria-hidden
            >
              {Array.from({ length: 36 }).map((_, i) => (
                <Sticker
                  key={i}
                  id={MINI_GAMES[currentGameIndex].id}
                  diecut={false}
                  className="w-full aspect-square"
                />
              ))}
            </div>

            <div className="relative z-10 text-center">
              <motion.div
                initial={{ y: 20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                className="bg-brand-accent/20 w-fit px-4 py-1 rounded-md text-[10px] font-black tracking-[0.3em] mb-4 mx-auto border border-brand-accent/30 text-brand-accent uppercase"
              >
                Round {played.length} of {ROUNDS_PER_MATCH}
              </motion.div>

              <motion.div
                key={MINI_GAMES[currentGameIndex].id}
                initial={{ scale: 0.2, rotate: -40, opacity: 0 }}
                animate={{ scale: 1, rotate: -6, opacity: 1 }}
                transition={{ type: "spring", stiffness: 260, damping: 14 }}
                className="mx-auto mb-2 w-[min(40vmin,15rem)] aspect-square"
              >
                <Sticker
                  id={MINI_GAMES[currentGameIndex].id}
                  title={MINI_GAMES[currentGameIndex].name}
                  className="w-full h-full"
                />
              </motion.div>

              <motion.h1
                initial={{ scale: 0.9, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                className="text-9xl font-black italic tracking-tighter mb-8 text-white uppercase drop-shadow-[0_0_30px_rgba(255,255,255,0.2)]"
              >
                {MINI_GAMES[currentGameIndex].name}
              </motion.h1>

              {!roomId || myPlayerId === 0 ? (
                <button
                  onClick={enterArena}
                  className="px-16 py-6 bg-white text-brand-bg font-black text-2xl hover:bg-brand-cyan transition-all uppercase tracking-widest cursor-pointer active:scale-95 rounded-2xl shadow-2xl"
                  id="start-button"
                >
                  Enter Arena
                </button>
              ) : (
                <div className="text-xl font-bold text-brand-cyan animate-pulse uppercase tracking-[0.5em]">
                  Waiting for Host...
                </div>
              )}
            </div>
          </motion.div>
        )}

        {gameState === "PLAYING" && (
          <motion.div
            key="playing"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="h-screen"
          >
            {renderGame()}
          </motion.div>
        )}

        {gameState === "GAME_END" && (
          <motion.div
            key="game-end"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="h-screen flex flex-col items-center justify-center bg-brand-bg/95 backdrop-blur-md p-8"
          >
            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full h-full opacity-10 bg-[radial-gradient(circle_at_center,_var(--color-brand-accent)_0%,_transparent_70%)]" />

            <div className="relative z-10 text-center">
              <div className="w-32 h-32 bg-brand-gold rounded-3xl flex items-center justify-center mx-auto mb-8 shadow-[0_0_50px_rgba(255,215,0,0.4)] rotate-12">
                <Trophy className="w-16 h-16 text-brand-bg" strokeWidth={3} />
              </div>

              <h2 className="text-5xl font-black mb-12 uppercase italic tracking-tighter">
                Round <span className="text-brand-accent">Concluded</span>
              </h2>

              <div className="flex flex-wrap justify-center gap-6 mb-16">
                {lastGameWinners.length > 0 ? (
                  lastGameWinners.map((id) => (
                    <div
                      key={id}
                      className="flex flex-col items-center p-8 bg-brand-card rounded-3xl border-2 border-brand-accent/30 min-w-[240px] shadow-xl"
                      style={{
                        borderBottomWidth: "8px",
                        borderBottomColor: players.find((p) => p.id === id)
                          ?.color,
                      }}
                    >
                      <span className="text-3xl font-black italic uppercase tracking-tight">
                        {players.find((p) => p.id === id)?.name}
                      </span>
                      <span className="text-xs opacity-50 uppercase font-black tracking-[0.2em] mt-2">
                        Top Performer
                      </span>
                    </div>
                  ))
                ) : (
                  <span className="text-2xl opacity-40 italic font-bold">
                    DRAW! NO WINNERS
                  </span>
                )}
              </div>

              {!roomId || myPlayerId === 0 ? (
                <button
                  onClick={nextPhase}
                  className="flex items-center gap-4 px-14 py-6 bg-brand-accent text-white font-black text-xl hover:bg-brand-accent/80 transition-all uppercase tracking-widest group cursor-pointer active:scale-95 rounded-2xl shadow-xl"
                  id="next-game-button"
                >
                  {played.length < ROUNDS_PER_MATCH
                    ? "Next Phase"
                    : "Final Standings"}
                  <ChevronRight
                    className="group-hover:translate-x-2 transition-transform w-8 h-8"
                    strokeWidth={3}
                  />
                </button>
              ) : (
                <div className="text-xl font-bold text-brand-accent animate-pulse uppercase tracking-[0.3em]">
                  Waiting for Command...
                </div>
              )}
            </div>
          </motion.div>
        )}

        {gameState === "SCOREBOARD" && (
          <motion.div
            key="scoreboard"
            initial={{ opacity: 0, x: 100 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -100 }}
            className="h-screen"
          >
            <Scoreboard players={players} onRestart={resetToLobby} />
          </motion.div>
        )}
      </AnimatePresence>

      {roomId && !online && (
        <div
          role="status"
          className="fixed bottom-6 left-1/2 -translate-x-1/2 z-[60] flex items-center gap-3 px-5 py-3 rounded-2xl bg-brand-card/95 border border-brand-accent/40 shadow-2xl backdrop-blur-xl"
        >
          <WifiOff className="w-5 h-5 text-brand-accent animate-pulse" />
          <span className="text-xs font-black italic uppercase tracking-widest">
            Reconnecting… your seat is saved
          </span>
        </div>
      )}
    </div>
  );
}
