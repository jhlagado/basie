/** Linker Phase E reports: the map and the debugger symbol file (linker §8). */
import type { Profile } from "../object/library.ts";
import { Kind, Pseudo } from "../object/types.ts";
import type { LinkResult } from "./link.ts";

const KIND_NAMES: Record<number, string> = {
  [Kind.code]: "code",
  [Kind.rodata]: "rodata",
  [Kind.data]: "data",
  [Kind.bss]: "bss",
  [Kind.startup]: "startup",
};

export type MapInputs = {
  programName: string;
  libraryName: string;
  runtimeIdentity: number;
  profileIdentity: number;
  outputKind: string;
  profile: Profile;
  /** Names from the name stream and the library's name section. */
  names?: Map<number, string>;
};

const h4 = (n: number) => n.toString(16).toUpperCase().padStart(4, "0");

/** The link map: summary, live blobs, removed blobs and totals. */
export function writeMap(result: LinkResult, inputs: MapInputs): string {
  const p = result.pseudo;
  const name = (o: number) => inputs.names?.get(o) ?? "";
  const imageEnd = result.imageBase + result.image.length;
  const bss = p.get(Pseudo.BSS)!;
  const required = p.get(Pseudo.REQUIRED)!.address;
  const lines: string[] = [];
  lines.push(`BASIE LINK MAP: ${inputs.programName}`);
  lines.push("");
  lines.push(`Library            ${inputs.libraryName}`);
  lines.push(
    `Runtime, profile   ${inputs.runtimeIdentity}, ${inputs.profileIdentity}`,
  );
  lines.push(`Output             ${inputs.outputKind}`);
  lines.push(
    `Image              $${h4(result.imageBase)} to $${
      h4(imageEnd)
    }, ${result.image.length} bytes`,
  );
  lines.push(`BSS                $${h4(bss.address)}, ${bss.size} bytes`);
  lines.push(
    `Stack reserve      ${result.stackReserve} bytes; largest frame ${result.largestFrame}${
      result.recursive ? "; recursion present" : ""
    }`,
  );
  lines.push(`Required top       $${h4(required)}`);
  lines.push(
    `Image limit        $${h4(inputs.profile.imageLimit)}, margin ${
      inputs.profile.imageLimit - imageEnd
    }`,
  );
  lines.push(
    `Nominal top        $${h4(inputs.profile.nominalTop)}, margin ${
      inputs.profile.nominalTop - required
    }`,
  );
  lines.push(
    `Under a debugger   margin ${
      inputs.profile.nominalTop - inputs.profile.debuggerMargin - required
    }`,
  );
  lines.push("");
  lines.push("LIVE BLOBS");
  lines.push("Address  Size  Kind     Pad  Ordinal  Name");
  const live = result.blobs.filter((b) => b.live).sort((a, b) =>
    a.address! - b.address!
  );
  for (const b of live) {
    lines.push(
      `$${h4(b.address!)}  ${String(b.size).padStart(5)}  ${
        KIND_NAMES[b.kind].padEnd(7)
      }  ${String(b.padding).padStart(3)}  $${h4(b.ordinal)}    ${
        name(b.ordinal)
      }`,
    );
  }
  lines.push("");
  lines.push("REMOVED BLOBS");
  lines.push("Ordinal  Size  Kind     Name");
  // Removed blobs in directory order, library first (linker §8.1).
  const removed = result.blobs.filter((b) => !b.live).sort((a, b) =>
    a.sequence - b.sequence
  );
  for (const b of removed) {
    lines.push(
      `$${h4(b.ordinal)}  ${String(b.size).padStart(5)}  ${
        KIND_NAMES[b.kind].padEnd(7)
      }  ${name(b.ordinal)}`,
    );
  }
  lines.push("");
  const total = (owner: string, isLive: boolean) =>
    result.blobs.filter((b) => b.owner === owner && b.live === isLive)
      .reduce((n, b) => n + b.size, 0);
  lines.push("TOTALS");
  lines.push(
    `Program   kept ${total("program", true)}, removed ${
      total("program", false)
    }`,
  );
  lines.push(
    `Library   kept ${total("library", true)}, removed ${
      total("library", false)
    }`,
  );
  return lines.join("\r\n") + "\r\n";
}

/**
 * A symbol file for SID and ZSID: four hex digits, a space, the name
 * (at most 16 characters), CR LF, ending with Control-Z. Blobs first in
 * address order, then aliases.
 */
export function writeSymbols(
  result: LinkResult,
  names: Map<number, string>,
  aliases: Set<number> = new Set(),
): Uint8Array {
  const rows: string[] = [];
  const named = [...result.addresses.entries()].filter(([o]) => names.has(o));
  const blobs = named.filter(([o]) => !aliases.has(o)).sort((a, b) =>
    a[1] - b[1]
  );
  const aliasRows = named.filter(([o]) => aliases.has(o)).sort((a, b) =>
    a[1] - b[1]
  );
  for (const [o, a] of [...blobs, ...aliasRows]) {
    rows.push(`${h4(a)} ${names.get(o)!.slice(0, 16)}`);
  }
  return new TextEncoder().encode(rows.join("\r\n") + "\r\n\x1a");
}
