// Find global labels that can become private: every reference lies inside the
// segment between the surrounding labels that stay global, in the same file.
import { Def, scan } from "./labels.ts";

export const ENTRIES = ["native/linker/BLINK.ASM"];

// Globals kept on purpose although one scope uses them: extent markers.
const keepGlobal = new Set(["FREEMEM"]);

// Names that host code looks up in the symbol table. BLINK's tests run the
// image and read no symbol, so none is pinned today; list any that become so.
const PINNED: string[] = [];
export function externalNames(_root: string) {
  return Promise.resolve(new Set(PINNED));
}

export async function analyse(root: string) {
  const ext = await externalNames(root);
  const result: {
    entry: string;
    demote: Def[];
    keep: Def[];
    defs: Def[];
    pinned: Set<string>;
  }[] = [];
  for (const entry of ENTRIES) {
    const { defs, refs, lines, files } = await scan(root, entry);
    const labels = defs.filter((d) => d.kind === "label");
    const refsBy = new Map<string, number[]>();
    for (const r of refs) {
      if (!r.privateRef) {
        (refsBy.get(r.name) ?? refsBy.set(r.name, []).get(r.name)!).push(
          r.order,
        );
      }
    }
    const fileOf = new Map(labels.map((d) => [d.order, d.file]));
    const fileEnd = new Map<string, number>();
    for (const l of lines) fileEnd.set(l.file, (fileEnd.get(l.file) ?? 0) + 1);
    {
      let acc = 0;
      for (const f of files) {
        acc += fileEnd.get(f)!;
        fileEnd.set(f, acc);
      }
    }
    const kept = labels.map(() => true);
    const pinned = (d: Def) => ext.has(d.name);
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < labels.length; i++) {
        if (!kept[i] || pinned(labels[i])) continue;
        let p = i - 1;
        while (p >= 0 && !kept[p]) p--;
        let n = i + 1;
        while (n < labels.length && !kept[n]) n++;
        if (p < 0 || labels[p].file !== labels[i].file) continue; // needs an owning global in this file
        if (keepGlobal.has(labels[i].name)) continue;
        const lo = labels[p].order;
        const hi = n < labels.length && labels[n].file === labels[i].file
          ? labels[n].order
          : fileEnd.get(labels[i].file)!;
        const rs = refsBy.get(labels[i].name) ?? [];
        if (rs.every((o) => o > lo && o < hi)) {
          kept[i] = false;
          changed = true;
        }
      }
    }
    void fileOf;
    result.push({
      entry,
      defs,
      demote: labels.filter((_, i) => !kept[i]),
      keep: labels.filter((_, i) => kept[i]),
      pinned: new Set(labels.filter((d) => ext.has(d.name)).map((d) => d.name)),
    });
  }
  return result;
}

if (import.meta.main) {
  const res = await analyse(Deno.args[0]);
  for (const r of res) {
    const equs = r.defs.filter((d) => d.kind === "equ").length;
    console.log(
      r.entry,
      "labels",
      r.demote.length + r.keep.length,
      "demotable",
      r.demote.length,
      "kept",
      r.keep.length,
      "equ",
      equs,
    );
  }
}
