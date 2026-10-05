// Print the image hash, length and symbol table of each entry, as JSON.
// Usage: deno run --config deno.runtime.json -A tools/labels/fingerprint.ts <repo>
import { createHash } from "node:crypto";
import { join } from "node:path";
import { assembleFile, comBytes } from "../../tests/harness/cpm.ts";
import { ENTRIES } from "./demote.ts";

const root = Deno.args[0] ?? Deno.cwd();
const out: Record<string, unknown> = {};
for (const entry of ENTRIES) {
  try {
    const r = await assembleFile(join(root, entry));
    const com = comBytes(r);
    const hash = createHash("sha256").update(com).digest("hex");
    const symbols = r.symbols.map(([n, v]) => [n.toUpperCase(), v]);
    out[entry] = { length: com.length, hash, symbols };
    console.error(entry, com.length, hash, symbols.length);
  } catch (e) {
    console.error(entry, "FAILED", String(e).slice(0, 300));
    out[entry] = { error: String(e) };
  }
}
console.log(JSON.stringify(out));
