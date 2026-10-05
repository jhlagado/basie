/**
 * The reference toolchain from the command line: compile and link one Basie
 * program to a CP/M .COM file, as BASIE.COM and BLINK.COM will on CP/M.
 *
 * Usage: deno task basie NAME.BSI [OUT.COM]
 *
 * The output defaults to NAME.COM beside the source. Includes are found
 * beside the including file first, then in lib/. A diagnostic is printed as
 * PART line:column: number: text, and the exit status is 1.
 */
import { compile } from "../ref/compile/index.ts";

if (import.meta.main) {
  const [source, out] = Deno.args;
  if (!source) {
    console.error("Usage: deno task basie NAME.BSI [OUT.COM]");
    Deno.exit(2);
  }
  const target = out ?? source.replace(/\.[^./]*$/, "") + ".COM";
  const result = await compile(source);
  if (!result.ok) {
    if ("linkError" in result) {
      console.error(`link error ${result.linkError}`);
    } else {
      for (const d of result.diagnostics) {
        const text = d.message.replace(/^\S+ at \d+:\d+: /, "");
        console.error(`${d.part} ${d.line}:${d.column}: ${d.number}: ${text}`);
      }
    }
    Deno.exit(1);
  }
  await Deno.writeFile(target, result.com);
  console.log(`${target}: ${result.imageSize} bytes`);
}
