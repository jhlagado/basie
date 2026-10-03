/**
 * Budget census: assemble an ATOM program and report how many bytes of its
 * image each source file and directory contributes.
 *
 *   deno task census ENTRY.asm [--budget BYTES] [--base ADDRESS]
 *
 * Bytes are attributed by label: each label owns the bytes from its address up
 * to the next label's, and belongs to the file that defines it. With --budget,
 * the census exits with status 1 when the image is larger, which is how the
 * native compiler and linker are held to their limits.
 */
import { walk } from "@std/fs/walk";
import { dirname, relative } from "@std/path";
import { assembleFile } from "../tests/harness/cpm.ts";

export type Census = {
  total: number;
  byFile: Map<string, number>;
  byDirectory: Map<string, number>;
};

/** Map each label defined in the sources under `root` to its file. */
export async function labelFiles(root: string) {
  const owner = new Map<string, string>();
  for await (const entry of walk(root, { exts: [".asm", ".inc"] })) {
    const text = await Deno.readTextFile(entry.path);
    for (const line of text.split("\n")) {
      const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*):/);
      if (m && !/\bEQU\b/i.test(line)) {
        owner.set(m[1].toLowerCase(), relative(root, entry.path));
      }
    }
  }
  return owner;
}

/** Attribute an assembled image's bytes to the files that define its labels. */
export function attribute(
  symbols: ReadonlyArray<readonly [string, number]>,
  owner: Map<string, string>,
  start: number,
  end: number,
): Census {
  const labels = symbols
    .filter(([name, value]) => owner.has(name) && value >= start && value < end)
    .sort((a, b) => a[1] - b[1]);
  const byFile = new Map<string, number>();
  const byDirectory = new Map<string, number>();
  for (let i = 0; i < labels.length; i += 1) {
    const span = (i + 1 < labels.length ? labels[i + 1][1] : end) -
      labels[i][1];
    const file = owner.get(labels[i][0])!;
    byFile.set(file, (byFile.get(file) ?? 0) + span);
    const dir = dirname(file);
    byDirectory.set(dir, (byDirectory.get(dir) ?? 0) + span);
  }
  return { total: end - start, byFile, byDirectory };
}

function table(map: Map<string, number>, total: number) {
  return [...map.entries()].sort((a, b) => b[1] - a[1]).map(([name, bytes]) =>
    `${String(bytes).padStart(7)}  ${
      (100 * bytes / total).toFixed(1).padStart(5)
    }%  ${name}`
  ).join("\n");
}

if (import.meta.main) {
  const args = [...Deno.args];
  const option = (name: string) => {
    const at = args.indexOf(name);
    if (at < 0) return undefined;
    const value = args[at + 1];
    args.splice(at, 2);
    return value;
  };
  const budget = option("--budget");
  const base = Number(option("--base") ?? 0x100);
  const entry = args[0];
  if (!entry) {
    console.error("usage: census ENTRY.asm [--budget BYTES] [--base ADDRESS]");
    Deno.exit(2);
  }
  const path = await Deno.realPath(entry);
  const image = await assembleFile(path);
  const symbols = image.symbols;
  const owner = await labelFiles(dirname(path));
  const census = attribute(symbols, owner, base, image.end);
  console.log(`Image: ${census.total} bytes from $${base.toString(16)}`);
  console.log("\nBy directory:\n" + table(census.byDirectory, census.total));
  console.log("\nBy file:\n" + table(census.byFile, census.total));
  if (budget !== undefined && census.total > Number(budget)) {
    console.log(`\nOver budget: ${census.total} > ${budget}`);
    Deno.exit(1);
  }
}
