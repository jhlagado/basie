// Reassemble every entry and require a byte-identical image and preserved
// symbol values after a rename.
// Usage: deno run --config deno.runtime.json -A tools/labels/verify.ts \
//          <repo> <baseline.json> [maps-dir]
import { join } from "node:path";
import { walkFiles } from "./labels.ts";

type Print = {
  error?: string;
  hash: string;
  length: number;
  symbols: [string, number][];
};
const [root, basePath, mapsDir] = Deno.args;
const base = JSON.parse(await Deno.readTextFile(basePath));
const globals = new Map<string, string>();
if (mapsDir) {
  for await (const p of walkFiles(mapsDir, [".json"])) {
    const m = JSON.parse(await Deno.readTextFile(p));
    for (const [o, n] of Object.entries<string>(m.globals ?? {})) {
      globals.set(o.toUpperCase(), n.toUpperCase());
    }
  }
}
const out = await new Deno.Command("deno", {
  args: [
    "run",
    "--config",
    join(root, "deno.runtime.json"),
    "-A",
    join(root, "tools/labels/fingerprint.ts"),
    root,
  ],
  stdout: "piped",
  stderr: "inherit",
}).output();
const now = JSON.parse(new TextDecoder().decode(out.stdout));
let ok = true;
for (const [entry, b] of Object.entries<Print>(base)) {
  const n: Print = now[entry];
  if (n.error) {
    console.log(`FAIL ${entry}: ${n.error.slice(0, 2000)}`);
    ok = false;
    continue;
  }
  if (n.hash !== b.hash) {
    console.log(`FAIL ${entry}: image differs (${b.length} -> ${n.length})`);
    ok = false;
  }
  const syms = new Map<string, number>(n.symbols);
  let missing = 0;
  for (const [name, value] of b.symbols) {
    if (name.startsWith(".")) continue;
    const to = globals.get(name) ?? name;
    if (to.startsWith(".")) continue;
    if (syms.get(to) !== value) {
      if (missing++ < 10) {
        console.log(
          `FAIL ${entry}: ${name} -> ${to} = ${syms.get(to)} expected ${value}`,
        );
      }
      ok = false;
    }
  }
  console.log(
    `${entry}: ${n.length} bytes, ${n.symbols.length} symbols${
      n.hash === b.hash ? ", identical" : ""
    }`,
  );
}
console.log(ok ? "VERIFIED" : "FAILED");
if (!ok) Deno.exit(1);
