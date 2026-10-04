/**
 * Writing, publishing and cleaning up a build's outputs (toolchain §3, §6).
 */
import { type Disk, DiskError } from "./disk.ts";

export type BuildOutputs = {
  /** Output extension: "COM", "BIN" or "HEX". */
  kind: string;
  image: Uint8Array;
  lineTable?: Uint8Array;
  map?: string;
  symbols?: Uint8Array;
};

export type PublishOptions = {
  /** Output drive and base name, as "B:HELLO" or "HELLO". */
  output: string;
  /** Spool drive and base name of the intermediate files. */
  spool: string;
  /** Option Z: don't keep a .BAK. */
  noBackup?: boolean;
  /** Option K: keep the intermediate files. */
  keepIntermediates?: boolean;
};

export type PublishResult = {
  published: boolean;
  /** Messages for the console, in order. */
  messages: string[];
};

export const INTERMEDIATES = ["$DR", "$BY", "$LN", "$NM", "$RF"];

/** Delete any file of the name first: make-file doesn't check (§3.2). */
function create(
  disk: Disk,
  name: string,
  bytes: Uint8Array,
  created: string[],
) {
  disk.delete(name);
  created.push(name);
  disk.write(name, bytes);
}

function removeIntermediates(disk: Disk, spool: string) {
  for (const ext of INTERMEDIATES) disk.delete(`${spool}.${ext}`);
}

/**
 * Called after a successful link. Writes MAIN.$$$ and MAIN.$LT, publishes
 * them, writes the reports, and removes the intermediates unless K.
 */
export function publish(
  disk: Disk,
  outputs: BuildOutputs,
  options: PublishOptions,
): PublishResult {
  const out = options.output;
  const messages: string[] = [];
  const created: string[] = [];
  try {
    create(disk, `${out}.$$$`, outputs.image, created);
    if (outputs.lineTable) {
      create(disk, `${out}.$LT`, outputs.lineTable, created);
    }
  } catch (e) {
    if (!(e instanceof DiskError)) throw e;
    messages.push(`${e.file}: ${e.condition}`);
    for (const f of created) disk.delete(f);
    if (!options.keepIntermediates) removeIntermediates(disk, options.spool);
    return { published: false, messages };
  }

  // Publication (§6.1): not atomic, but never loses both versions.
  const target = `${out}.${outputs.kind}`;
  if (disk.exists(target)) {
    if (options.noBackup) disk.delete(target);
    else {
      disk.delete(`${out}.BAK`);
      disk.rename(target, `${out}.BAK`);
    }
  }
  disk.rename(`${out}.$$$`, target);
  if (outputs.lineTable) {
    disk.delete(`${out}.LIN`);
    disk.rename(`${out}.$LT`, `${out}.LIN`);
  } else {
    // Option N: a stale line table would mislead trap lookup.
    disk.delete(`${out}.LIN`);
  }

  const reports: [string, Uint8Array | undefined][] = [
    [
      "MAP",
      outputs.map === undefined
        ? undefined
        : new TextEncoder().encode(outputs.map),
    ],
    ["SYM", outputs.symbols],
  ];
  for (const [ext, bytes] of reports) {
    if (!bytes) continue;
    const name = `${out}.${ext}`;
    try {
      disk.delete(name);
      disk.write(name, bytes);
    } catch (e) {
      if (!(e instanceof DiskError)) throw e;
      messages.push(`${e.file}: ${e.condition}`);
      disk.delete(name);
    }
  }
  if (!options.keepIntermediates) removeIntermediates(disk, options.spool);
  return { published: true, messages };
}

/** After a source or link error: outputs untouched, temporaries removed. */
export function abandon(disk: Disk, options: PublishOptions): void {
  disk.delete(`${options.output}.$$$`);
  disk.delete(`${options.output}.$LT`);
  if (!options.keepIntermediates) removeIntermediates(disk, options.spool);
}
