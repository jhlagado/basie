/**
 * Trap lookup, `BASIE NAME [T=hhhh]` (toolchain §8, design decision D47):
 * the statement whose code holds an address, from NAME.LIN and the source.
 * The reference for BASIE.COM's option T, which prints the same text.
 */
import { crc16 } from "../object/crc.ts";
import { readLineTable } from "./linetable.ts";

/** What the lookup prints, each line ended by CR LF, and whether it failed. */
export type TrapLookup = { text: string; failed: boolean };

/**
 * Look address up for the program NAME, reading files through `read`
 * (undefined for a file that isn't there):
 *
 * - NAME.LIN missing or damaged, or no program file NAME.COM, NAME.BIN or
 *   NAME.HEX whose CRC is the table's image CRC: a failure;
 * - an address below the first entry: outside the stored code;
 * - one in a blob without source: its ordinal;
 * - otherwise `PART LINE:COLUMN  text`, the text the statement's line holds
 *   from its column on, or `PART LINE:COLUMN` alone when the part can't be
 *   read.
 */
export function trapLookup(
  name: string,
  address: number,
  read: (file: string) => Uint8Array | undefined,
): TrapLookup {
  const fail = (text: string) => ({ text: text + "\r\n", failed: true });
  const lin = read(`${name}.LIN`);
  if (!lin) return fail(`${name}.LIN not found`);
  let table;
  try {
    table = readLineTable(lin);
  } catch {
    return fail(`${name}.LIN is damaged`);
  }
  const programs = ["COM", "BIN", "HEX"]
    .map((type) => read(`${name}.${type}`))
    .filter((f): f is Uint8Array => f !== undefined);
  if (programs.length === 0) return fail(`${name}.COM not found`);
  if (!programs.some((f) => crc16(f) === table.imageCrc)) {
    return fail(`${name}.LIN doesn't match the program`);
  }
  const at = hex4(address);
  let best;
  for (const e of table.entries) {
    if (e.address > address) break;
    best = e;
  }
  const say = (text: string) => ({ text: text + "\r\n", failed: false });
  if (!best) return say(`${at} is outside the stored code`);
  if (best.part === 0xff) {
    return say(`${at} is in blob ${hex4(best.source)}, which has no source`);
  }
  const part = table.parts[best.part];
  const where = `${part} ${best.source}:${best.column}`;
  const source = read(part);
  if (!source) return say(where);
  return say(`${where}  ${lineText(source, best.source, best.column)}`);
}

/** Line `line` of a source part from column `column` on, without its end. */
function lineText(source: Uint8Array, line: number, column: number): string {
  let start = 0;
  for (let n = 1; n < line && start < source.length; start += 1) {
    if (source[start] === 0x0a) n += 1;
  }
  let end = start;
  while (
    end < source.length && source[end] !== 0x0a && source[end] !== 0x0d &&
    source[end] !== 0x1a
  ) end += 1;
  const from = Math.min(start + column - 1, end);
  return String.fromCharCode(...source.subarray(from, end));
}

function hex4(n: number): string {
  return n.toString(16).toUpperCase().padStart(4, "0");
}
