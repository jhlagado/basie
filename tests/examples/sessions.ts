/**
 * The example programs' recorded sessions (roadmap step 58), shared by the
 * examples test and the release test: what to type, the command tail, the
 * files the program reads, and what a run under real CP/M must show.
 */
export type Session = {
  name: string;
  program: string;
  /** Console input; each line ends with a carriage return. */
  lines?: string[];
  tail?: string;
  files?: Record<string, string>;
  /** What the run must show under real CP/M. */
  shows: string[];
};

export const SESSIONS: Session[] = [
  {
    name: "advent-win",
    program: "ADVENT",
    lines: [
      "look",
      "help",
      "xyzzy",
      "e",
      "n",
      "take lamp",
      "w",
      "take key",
      "i",
      "e",
      "e",
      "e",
      "take gold",
      "w",
      "w",
      "s",
      "drop gold",
    ],
    shows: ["There is a key here.", "You win!"],
  },
  {
    name: "advent-locked",
    program: "ADVENT",
    lines: ["n", "e", "e", "drop lamp", "quit"],
    shows: ["It is too dark to see.", "The iron door is locked.", "Goodbye."],
  },
  {
    name: "bugs-win",
    program: "BUGS",
    lines: [
      "n",
      "n",
      "z e",
      "z s",
      "n",
      "z w",
      "s",
      "n",
      "s",
      "n",
      "s",
      "w",
      "z s",
      "z w",
      "z s",
      "z s",
      "z s",
    ],
    shows: ["Zap!", "The cave is safe. You win!"],
  },
  {
    name: "bugs-lose",
    program: "BUGS",
    lines: ["s", "s", "s"],
    shows: ["A bug got you!"],
  },
  {
    name: "dump",
    program: "DUMP",
    tail: "HELLO.TXT",
    files: { "HELLO.TXT": "Hello, Basie!\r\nTwo lines.\r\n" },
    shows: ["0000: 48 65 6C 6C 6F 2C 20 42  61 73 69 65 21 0D 0A 54"],
  },
  {
    name: "dump-usage",
    program: "DUMP",
    shows: ["Usage: DUMP NAME.EXT"],
  },
  {
    name: "dump-missing",
    program: "DUMP",
    tail: "NOPE.TXT",
    shows: ["No file NOPE.TXT"],
  },
];
