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

import { useState, useCallback, useEffect } from "react";
import { motion, AnimatePresence } from "motion/react";
import { GameState, Player, PLAYER_COLORS } from "./types";
import { createInitialPlayers, MINI_GAMES } from "./constants";
import Lobby from "./components/Lobby";
import Scoreboard from "./components/Scoreboard";
import ReactionGame from "./games/ReactionGame";
import MashGame from "./games/MashGame";
import PatternGame from "./games/PatternGame";
import StopGame from "./games/StopGame";
import CountGame from "./games/CountGame";
import TargetGame from "./games/TargetGame";
import TugGame from "./games/TugGame";
import BalanceGame from "./games/BalanceGame";
import MatchGame from "./games/MatchGame";
import FuelGame from "./games/FuelGame";
import ScanGame from "./games/ScanGame";
import DodgeGame from "./games/DodgeGame";
import SmashGame from "./games/SmashGame";
import {
  Trophy,
  ChevronRight,
  Share2,
  Users,
  Radio,
  Globe,
} from "lucide-react";
import { socketService } from "./services/socketService";

export default function App() {
  const [gameState, setGameState] = useState<GameState>("LOBBY");
  const [players, setPlayers] = useState<Player[]>([]);
  const [currentGameIndex, setCurrentGameIndex] = useState(0);
  const [lastGameWinners, setLastGameWinners] = useState<number[]>([]);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [myPlayerId, setMyPlayerId] = useState<number | null>(null);

  // Parse URL for room ID
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const room = params.get("room");
    if (room) setRoomId(room);
  }, []);

  const startGame = (playerCount: number) => {
    setPlayers(createInitialPlayers(playerCount));
    setCurrentGameIndex(0);
    setGameState("GAME_START");
  };

  const startRemoteGame = (playerName: string) => {
    const socket = socketService.connect();
    const id = roomId || Math.random().toString(36).substring(7).toUpperCase();
    setRoomId(id);

    // Update URL without refreshing
    const newUrl = `${window.location.origin}${window.location.pathname}?room=${id}`;
    window.history.replaceState({ path: newUrl }, "", newUrl);

    socketService.joinRoom(id, playerName, PLAYER_COLORS[0]); // Host or Joiner

    socketService.onRoomUpdate(({ players: remotePlayers }) => {
      setPlayers(remotePlayers);
      // Find my player ID
      const me = remotePlayers.find(
        (p: any) => p.socketId === socketService.getSocketId(),
      );
      if (me) setMyPlayerId(me.id);
    });

    socketService.onGameStarted(({ gameIndex }) => {
      setCurrentGameIndex(gameIndex);
      setGameState("GAME_START");
    });
  };

  const handleManualStart = () => {
    if (roomId) {
      socketService.startGame(0);
    } else {
      setGameState("PLAYING");
    }
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
    if (currentGameIndex < MINI_GAMES.length - 1) {
      if (roomId) {
        socketService.startGame(currentGameIndex + 1);
      } else {
        setCurrentGameIndex((prev) => prev + 1);
        setGameState("GAME_START");
      }
    } else {
      setGameState("SCOREBOARD");
    }
  };

  const resetToLobby = () => {
    setGameState("LOBBY");
    setPlayers([]);
    setCurrentGameIndex(0);
    setRoomId(null);
    setMyPlayerId(null);
    window.history.replaceState({}, "", window.location.pathname);
  };

  const renderGame = () => {
    const game = MINI_GAMES[currentGameIndex];
    // In multiplayer, we pass the "active" player or restrict inputs
    // For now, let's just pass the players. Games might need subtle tweaks to restrict input to myPlayerId.
    const props = { players, onEnd: handleGameEnd, myPlayerId };

    switch (game.id) {
      case "reaction":
        return <ReactionGame {...props} />;
      case "mash":
        return <MashGame {...props} />;
      case "pattern":
        return <PatternGame {...props} />;
      case "stop":
        return <StopGame {...props} />;
      case "count":
        return <CountGame {...props} />;
      case "target":
        return <TargetGame {...props} />;
      case "tug":
        return <TugGame {...props} />;
      case "balance":
        return <BalanceGame {...props} />;
      case "match":
        return <MatchGame {...props} />;
      case "fuel":
        return <FuelGame {...props} />;
      case "scan":
        return <ScanGame {...props} />;
      case "dodge":
        return <DodgeGame {...props} />;
      case "smash":
        return <SmashGame {...props} />;
      default:
        return <div>Unknown Game</div>;
    }
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
                        className="w-10 h-10 rounded-full border-2 border-white/20 shadow-lg"
                        style={{ backgroundColor: p.color }}
                        title={p.name}
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
                        onClick={() => handleManualStart()}
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
            <div className="absolute inset-0">
              <img
                src={`https://picsum.photos/seed/${MINI_GAMES[currentGameIndex].id}/1920/1080?grayscale&blur=2`}
                alt="Game Preview"
                className="w-full h-full object-cover opacity-20"
                referrerPolicy="no-referrer"
              />
              <div className="absolute inset-0 bg-gradient-to-br from-brand-bg via-brand-bg/60 to-brand-bg" />
            </div>

            <div className="relative z-10 text-center">
              <motion.div
                initial={{ y: 20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                className="bg-brand-accent/20 w-fit px-4 py-1 rounded-md text-[10px] font-black tracking-[0.3em] mb-4 mx-auto border border-brand-accent/30 text-brand-accent uppercase"
              >
                Upcoming Challenge
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
                  onClick={handleManualStart}
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
                  {currentGameIndex < MINI_GAMES.length - 1
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
    </div>
  );
}
