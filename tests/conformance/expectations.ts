/** Parsing of the expectation comments at the head of a conformance test. */

export type Expectations = {
  output?: string;
  trap?: { reason: string; line: number };
  error?: { code: string; line: number; column: number };
  linkError?: string;
  returnCode?: number;
  input: string;
  tail: string;
  files: Record<string, string>;
  expectFiles: Record<string, string>;
  /** Files that must not exist after the run. */
  absentFiles: string[];
  spec: string[];
};

/** Decode the escapes allowed in expectation text. */
export function unescape(text: string): string {
  return text.replace(
    /\\(x[0-9A-Fa-f]{2}|[rnt\\])/g,
    (_, code: string) => {
      switch (code) {
        case "r":
          return "\r";
        case "n":
          return "\n";
        case "t":
          return "\t";
        case "\\":
          return "\\";
        default:
          return String.fromCharCode(parseInt(code.slice(1), 16));
      }
    },
  );
}

function number(text: string): number {
  const value = text.startsWith("$")
    ? parseInt(text.slice(1), 16)
    : parseInt(text, 10);
  if (Number.isNaN(value)) throw new Error(`Bad number: ${text}`);
  return value;
}

/** Read the leading `//` lines of a test and return its expectations. */
export function parseExpectations(source: string): Expectations {
  const result: Expectations = {
    input: "",
    tail: "",
    files: {},
    expectFiles: {},
    absentFiles: [],
    spec: [],
  };
  let output: string[] | undefined;
  for (const raw of source.split(/\r?\n/)) {
    const line = raw.trim();
    if (line === "") continue;
    if (!line.startsWith("//")) break;
    const body = line.slice(2).trim();
    let m: RegExpMatchArray | null;
    if ((m = body.match(/^expect output: ?(.*)$/))) {
      (output ??= []).push(unescape(m[1]));
    } else if ((m = body.match(/^expect trap: (\S+) at (\d+)$/))) {
      result.trap = { reason: m[1], line: Number(m[2]) };
    } else if ((m = body.match(/^expect error: (\S+) at (\d+):(\d+)$/))) {
      result.error = { code: m[1], line: Number(m[2]), column: Number(m[3]) };
    } else if ((m = body.match(/^expect link error: (\S+)$/))) {
      result.linkError = m[1];
    } else if ((m = body.match(/^expect return: (\S+)$/))) {
      result.returnCode = number(m[1]);
    } else if ((m = body.match(/^input: ?(.*)$/))) {
      result.input += unescape(m[1]);
    } else if ((m = body.match(/^tail: ?(.*)$/))) {
      result.tail = unescape(m[1]);
    } else if ((m = body.match(/^expect no file (\S+)$/))) {
      result.absentFiles.push(m[1].toUpperCase());
    } else if ((m = body.match(/^expect file (\S+): ?(.*)$/))) {
      result.expectFiles[m[1].toUpperCase()] =
        (result.expectFiles[m[1].toUpperCase()] ?? "") + unescape(m[2]);
    } else if ((m = body.match(/^file (\S+): ?(.*)$/))) {
      result.files[m[1].toUpperCase()] =
        (result.files[m[1].toUpperCase()] ?? "") + unescape(m[2]);
    } else if ((m = body.match(/^spec: (.*)$/))) {
      result.spec.push(m[1]);
    }
    // Any other comment is description and is ignored.
  }
  if (output) result.output = output.join("");
  const failing = result.error !== undefined || result.linkError !== undefined;
  const running = result.output !== undefined || result.trap !== undefined ||
    result.returnCode !== undefined;
  if (failing && running) {
    throw new Error("A test states both a failure and a run result");
  }
  return result;
}
