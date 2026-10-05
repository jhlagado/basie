/**
 * The native linker, BLINK.COM (roadmap step 59: the skeleton): its command
 * line, files, CRC and diagnostics, under the CP/M harness.
 */
import { assertEquals } from "@std/assert";
import { formatMessage, messageFile } from "../ref/compile/messages.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";

const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
const library = (await buildRuntime()).file;
const MSG = messageFile();

function run(tail: string, files: Record<string, Uint8Array> = {}) {
  return runCom(blink, { tail, files }).output;
}

const error = (n: number, args: string[] = []) =>
  `Error ${n}: ${formatMessage(n, args)}\r\n`;

Deno.test("BLINK with no name prints its usage", () => {
  assertEquals(run("", { "BASIE.MSG": MSG }), error(223));
});

Deno.test("without BASIE.MSG a diagnostic gives its number and arguments", () => {
  assertEquals(run(""), "Error 223: Message 223\r\n");
  assertEquals(run("HELLO"), "Error 225: Message 225: CPM22.BRL\r\n");
});

Deno.test("BLINK finds and checks the library, and its CRC with V", () => {
  const files = { "BASIE.MSG": MSG, "CPM22.BRL": library };
  assertEquals(run("HELLO", files), "");
  assertEquals(run("HELLO [V]", files), "");
  const damaged = library.slice();
  damaged[200] ^= 1;
  assertEquals(
    run("HELLO [V]", { ...files, "CPM22.BRL": damaged }),
    error(214, ["CPM22.BRL"]),
  );
  assertEquals(run("HELLO", { ...files, "CPM22.BRL": damaged }), "");
  const foreign = library.slice();
  foreign[0] = 0x58;
  assertEquals(
    run("HELLO", { ...files, "CPM22.BRL": foreign }),
    error(200, ["CPM22.BRL"]),
  );
});

Deno.test("BLINK looks for the library named by P=", () => {
  assertEquals(
    run("HELLO [P=OTHER]", { "BASIE.MSG": MSG }),
    error(225, ["OTHER.BRL"]),
  );
  assertEquals(
    run("hello [p=other]", { "BASIE.MSG": MSG, "OTHER.BRL": library }),
    "",
  );
});

Deno.test("BLINK refuses bad and repeated options", () => {
  const files = { "BASIE.MSG": MSG, "CPM22.BRL": library };
  assertEquals(run("HELLO [Q]", files), error(224, ["Q"]));
  assertEquals(run("HELLO [M,M]", files), error(224, ["M"]));
  assertEquals(run("HELLO [F=0]", files), error(224, ["F=0"]));
  assertEquals(run("HELLO [F=256]", files), error(224, ["F=256"]));
  assertEquals(run("HELLO [L=Q]", files), error(224, ["L=Q"]));
  assertEquals(run("HELLO [M, Y, F=6, STACK=512, O=B:OUT.HEX]", files), "");
  assertEquals(run("HELLO,UTIL [K]", files), "");
  assertEquals(run("TOOLONGNAME", files), error(224, ["TOOLONGNAME"]));
});
