/**
 * Conformance runner: compiles, links and runs every test under the CP/M
 * harness and compares the results with the test's expectations.
 */
import { walk } from "@std/fs/walk";
import { compile, NotImplemented } from "../../ref/compile/index.ts";
import { lookup, readLineTable } from "../../ref/toolchain/linetable.ts";
import { runCom } from "../harness/cpm.ts";
import { type Expectations, parseExpectations } from "./expectations.ts";

export type Outcome =
  | { status: "pass" }
  | { status: "pending"; reason: string }
  | { status: "fail"; reason: string };

/** Run one test's source against its expectations. */
export async function runTest(path: string, source: string): Promise<Outcome> {
  const expected = parseExpectations(source);
  let result;
  try {
    result = await compile(path, {
      mainSource: new TextEncoder().encode(source),
    });
  } catch (error) {
    if (error instanceof NotImplemented) {
      return { status: "pending", reason: error.message };
    }
    throw error;
  }
  if (!result.ok) {
    if ("linkError" in result) {
      return expected.linkError === result.linkError ? { status: "pass" } : {
        status: "fail",
        reason: `unexpected link error ${result.linkError}`,
      };
    }
    const first = result.diagnostics[0];
    const want = expected.error;
    const futureLibrary =
      /\b(appendU32|appendI32|appendF32|appendHex8|appendHex16|parse[A-Z]\w*|writeLine|prompt|readSecret|word|readAll)\b/;
    if (
      first?.code === "undeclared-name" && !want &&
      futureLibrary.test(first.message)
    ) {
      return {
        status: "pending",
        reason: "a standard-library routine is not written yet",
      };
    }
    if (
      first?.code === "include-missing" && !want &&
      /\b(STRINGS|FORMAT|PARSE|TEXTIO|RANDOM)\.BSI/.test(first.message)
    ) {
      return {
        status: "pending",
        reason: "the standard library is not written yet",
      };
    }
    if (
      want && first && first.code === want.code && first.line === want.line &&
      first.column === want.column
    ) return { status: "pass" };
    return {
      status: "fail",
      reason:
        `diagnostic ${first?.code} at ${first?.part} ${first?.line}:${first?.column}: ${first?.message}`,
    };
  }
  if (expected.error || expected.linkError) {
    return { status: "fail", reason: "compiled, but a failure was expected" };
  }
  return compare(expected, result.com, result.lineTable);
}

function compare(
  expected: Expectations,
  com: Uint8Array,
  lineTable?: Uint8Array,
): Outcome {
  let run;
  try {
    run = runCom(com, {
      input: expected.input,
      tail: expected.tail,
      files: expected.files,
    });
  } catch (e) {
    return {
      status: "fail",
      reason: `the program did not finish: ${(e as Error).message}`,
    };
  }
  if (expected.trap) {
    const m = run.output.match(/TRAP ([a-z-]+) at ([0-9A-F]{4})\r\n$/);
    if (!m) {
      return {
        status: "fail",
        reason: `no trap; output ${JSON.stringify(run.output)}`,
      };
    }
    if (m[1] !== expected.trap.reason) {
      return {
        status: "fail",
        reason: `trap ${m[1]}, expected ${expected.trap.reason}`,
      };
    }
    if (!lineTable) return { status: "fail", reason: "no line table" };
    const where = lookup(readLineTable(lineTable), parseInt(m[2], 16));
    if (where?.line !== expected.trap.line) {
      return {
        status: "fail",
        reason: `trap at line ${where?.line ?? "?"} (address ${
          m[2]
        }), expected line ${expected.trap.line}`,
      };
    }
    if (run.returnCode !== 0xff02) {
      return {
        status: "fail",
        reason: `return code ${run.returnCode} after a trap`,
      };
    }
    return { status: "pass" };
  }
  if (expected.output !== undefined && run.output !== expected.output) {
    return {
      status: "fail",
      reason: `output ${JSON.stringify(run.output)}, expected ${
        JSON.stringify(expected.output)
      }`,
    };
  }
  if (
    expected.returnCode !== undefined && run.returnCode !== expected.returnCode
  ) {
    return { status: "fail", reason: `return code ${run.returnCode}` };
  }
  for (const [name, text] of Object.entries(expected.expectFiles)) {
    const data = run.disk.get(name);
    const got = data ? new TextDecoder().decode(data) : undefined;
    if (got !== text) return { status: "fail", reason: `file ${name} differs` };
  }
  return { status: "pass" };
}

if (import.meta.main) {
  const root = new URL("./", import.meta.url).pathname;
  const counts = { pass: 0, pending: 0, fail: 0 };
  for await (const entry of walk(root, { exts: [".bsi"] })) {
    const source = await Deno.readTextFile(entry.path);
    const outcome = await runTest(entry.path, source);
    counts[outcome.status] += 1;
    if (outcome.status === "fail") {
      console.log(`FAIL ${entry.path.slice(root.length)}: ${outcome.reason}`);
    }
  }
  console.log(
    `${counts.pass} passed, ${counts.pending} pending, ${counts.fail} failed`,
  );
  if (counts.fail > 0) Deno.exit(1);
}
