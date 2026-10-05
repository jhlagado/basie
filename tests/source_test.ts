import { assertEquals, assertThrows } from "@std/assert";
import { CompileError } from "../ref/compile/diagnostics.ts";
import { loadSource, type Reader } from "../ref/compile/source.ts";

const enc = (s: string) => new TextEncoder().encode(s);

function memory(files: Record<string, string>): Reader {
  return {
    read: (path) => path in files ? enc(files[path]) : undefined,
  };
}

const show = (
  path: string,
  files: Record<string, string>,
  libs: string[] = [],
) => {
  const s = loadSource(path, { reader: memory(files), libraryDirs: libs });
  return {
    parts: s.parts.map((p) => p.name),
    tokens: s.tokens.map((t) =>
      `${t.part}:${
        t.kind === "name"
          ? t.text
          : t.kind === "keyword"
          ? t.text.toUpperCase()
          : t.kind
      }`
    ).join(" "),
  };
};

Deno.test("an included part is compiled before the rest of the part", () => {
  const r = show("/p/main.bsi", {
    "/p/main.bsi": 'include "UTIL.BSI"\nconst a = 1\n',
    "/p/UTIL.BSI": "const b = 2\n",
  });
  assertEquals(r.parts, ["UTIL.BSI", "MAIN.BSI"]);
  assertEquals(
    r.tokens,
    "0:CONST 0:b 0:punct 0:number 0:newline 1:CONST 1:a 1:punct 1:number 1:newline 1:eof",
  );
});

Deno.test("includes are depth first and once only", () => {
  const r = show("/p/main.bsi", {
    "/p/main.bsi": 'include "A.BSI"\ninclude "B.BSI"\nconst m = 0\n',
    "/p/A.BSI": 'include "C.BSI"\nconst a = 0\n',
    "/p/B.BSI": 'include "C.BSI"\nconst b = 0\n',
    "/p/C.BSI": "const c = 0\n",
  });
  assertEquals(r.parts, ["C.BSI", "A.BSI", "B.BSI", "MAIN.BSI"]);
  assertEquals(r.tokens.match(/:c /g)!.length, 1);
});

Deno.test("the library directory is searched after the part's own", () => {
  const r = show("/p/main.bsi", {
    "/p/main.bsi": 'include "FORMAT.BSI"\n',
    "/lib/FORMAT.BSI": "const f = 0\n",
  }, ["/lib"]);
  assertEquals(r.parts, ["FORMAT.BSI", "MAIN.BSI"]);
});

Deno.test("include diagnostics: missing, cycle, position", () => {
  const code = (files: Record<string, string>) =>
    assertThrows(
      () => loadSource("/p/main.bsi", { reader: memory(files) }),
      CompileError,
    )
      .code;
  assertEquals(
    code({ "/p/main.bsi": 'include "NOPE.BSI"\n' }),
    "include-missing",
  );
  assertEquals(
    code({
      "/p/main.bsi": 'include "A.BSI"\n',
      "/p/A.BSI": 'include "MAIN.BSI"\n',
    }),
    "include-cycle",
  );
  const e = assertThrows(
    () =>
      loadSource("/p/main.bsi", {
        reader: memory({
          "/p/main.bsi": 'const x = 1\ninclude "A.BSI"\n',
          "/p/A.BSI": "",
        }),
      }),
    CompileError,
  );
  assertEquals([e.code, e.position.line], ["include-position", 2]);
});

Deno.test("a part with no final newline still ends its last line", () => {
  const r = show("/p/main.bsi", {
    "/p/main.bsi": 'include "A.BSI"\nconst m = 0',
    "/p/A.BSI": "const a = 0",
  });
  assertEquals(
    r.tokens.endsWith("0:newline 1:CONST 1:m 1:punct 1:number 1:newline 1:eof"),
    true,
  );
});
