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

// SUM! — quick sums. Tap the right answer out of three; a wrong tap costs
// points. Everyone gets the same questions in the same order.

import { useMemo, useState } from "react";
import { Player } from "../types";
import {
  ChoiceButton,
  GameScreen,
  PlayerPanels,
  useRound,
  type GameProps,
  type Round,
} from "../kit/round";
import { randInt, shuffle } from "../kit/logic";

export const sticker = (
  <>
    <rect x="10" y="14" width="100" height="92" rx="18" fill="#00F2FF" />
    <path d="M38 40 v40 M18 60 h40" stroke="#0F0C29" strokeWidth="10" strokeLinecap="round" />
    <path d="M70 50 h30 M70 70 h30" stroke="#FFFFFF" strokeWidth="10" strokeLinecap="round" />
  </>
);

interface Question {
  text: string;
  answer: number;
  options: number[];
}

function makeQuestions(rand: () => number, count: number): Question[] {
  return Array.from({ length: count }, (_, i) => {
    // Gets harder as you go: bigger numbers, then times tables.
    const hard = i >= 8;
    let a: number, b: number, text: string, answer: number;
    const kind = hard ? randInt(rand, 0, 2) : randInt(rand, 0, 1);
    if (kind === 2) {
      a = randInt(rand, 2, 9);
      b = randInt(rand, 2, 9);
      text = `${a} × ${b}`;
      answer = a * b;
    } else if (kind === 1) {
      a = randInt(rand, hard ? 20 : 6, hard ? 60 : 20);
      b = randInt(rand, 1, a - 1);
      text = `${a} − ${b}`;
      answer = a - b;
    } else {
      a = randInt(rand, hard ? 12 : 1, hard ? 49 : 12);
      b = randInt(rand, hard ? 12 : 1, hard ? 49 : 12);
      text = `${a} + ${b}`;
      answer = a + b;
    }
    const wrong = new Set<number>();
    while (wrong.size < 2) {
      const off = randInt(rand, 1, 4) * (rand() < 0.5 ? -1 : 1);
      if (answer + off >= 0) wrong.add(answer + off);
    }
    return { text, answer, options: shuffle(rand, [answer, ...wrong]) };
  });
}

function Board({ player, round, questions }: { player: Player; round: Round; questions: Question[] }) {
  const [index, setIndex] = useState(0);
  const [flash, setFlash] = useState<{ value: number; ok: boolean } | null>(null);
  const q = questions[index % questions.length];
  const active = round.canPlay(player.id) && !flash;

  const answer = (value: number) => {
    const ok = value === q.answer;
    round.addScore(player.id, ok ? 10 : -5);
    setFlash({ value, ok });
    window.setTimeout(() => {
      setFlash(null);
      setIndex((i) => i + 1);
    }, ok ? 180 : 450);
  };

  return (
    <div className="h-full flex flex-col items-center justify-center gap-4 p-4">
      <div className="text-5xl sm:text-6xl font-black italic tabular-nums">{q.text}</div>
      <div className="grid grid-cols-3 gap-3 w-full max-w-md">
        {q.options.map((value) => (
          <ChoiceButton
            key={`${index}-${value}`}
            onClick={() => answer(value)}
            disabled={!active}
            tone={flash?.value === value ? (flash.ok ? "good" : "bad") : "default"}
            className="py-5 tabular-nums"
          >
            {value}
          </ChoiceButton>
        ))}
      </div>
    </div>
  );
}

export default function MathGame(props: GameProps) {
  const round = useRound(props, { gameId: "math", seconds: 25 });
  const questions = useMemo(() => makeQuestions(round.random(), 60), [round.random]);
  return (
    <GameScreen
      round={round}
      players={props.players}
      title="SUM!"
      howTo="Tap the right answer"
      detail="+10 right · −5 wrong"
    >
      <PlayerPanels round={round} players={props.players}>
        {(player) => <Board player={player} round={round} questions={questions} />}
      </PlayerPanels>
    </GameScreen>
  );
}
