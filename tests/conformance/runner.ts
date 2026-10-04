/**
 * Conformance runner: compiles, links and runs every test under the CP/M
 * harness and compares the results with the test's expectations.
 */
import { walk } from "@std/fs/walk";
import { compile, NotImplemented } from "../../ref/compile/index.ts";
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
    if (
      first?.code === "include-missing" && !want &&
      /\b(STRINGS|FORMAT|PARSE|TEXTIO|RANDOM)\.BTN/.test(first.message)
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
      reason: `diagnostic ${first?.code} at ${first?.line}:${first?.column}`,
    };
  }
  if (expected.error || expected.linkError) {
    return { status: "fail", reason: "compiled, but a failure was expected" };
  }
  return compare(expected, result.com);
}

function compare(expected: Expectations, com: Uint8Array): Outcome {
  const run = runCom(com, {
    input: expected.input,
    tail: expected.tail,
    files: expected.files,
  });
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
  // Trap expectations are checked once the line table exists.
  if (expected.trap) {
    return { status: "pending", reason: "trap checks need the line table" };
  }
  return { status: "pass" };
}

if (import.meta.main) {
  const root = new URL("./", import.meta.url).pathname;
  const counts = { pass: 0, pending: 0, fail: 0 };
  for await (const entry of walk(root, { exts: [".btn"] })) {
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
