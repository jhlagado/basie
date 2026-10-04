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
  const r = show("/p/main.btn", {
    "/p/main.btn": 'include "UTIL.BTN"\nconst a = 1\n',
    "/p/UTIL.BTN": "const b = 2\n",
  });
  assertEquals(r.parts, ["UTIL.BTN", "MAIN.BTN"]);
  assertEquals(
    r.tokens,
    "0:CONST 0:b 0:punct 0:number 0:newline 1:CONST 1:a 1:punct 1:number 1:newline 1:eof",
  );
});

Deno.test("includes are depth first and once only", () => {
  const r = show("/p/main.btn", {
    "/p/main.btn": 'include "A.BTN"\ninclude "B.BTN"\nconst m = 0\n',
    "/p/A.BTN": 'include "C.BTN"\nconst a = 0\n',
    "/p/B.BTN": 'include "C.BTN"\nconst b = 0\n',
    "/p/C.BTN": "const c = 0\n",
  });
  assertEquals(r.parts, ["C.BTN", "A.BTN", "B.BTN", "MAIN.BTN"]);
  assertEquals(r.tokens.match(/:c /g)!.length, 1);
});

Deno.test("the library directory is searched after the part's own", () => {
  const r = show("/p/main.btn", {
    "/p/main.btn": 'include "FORMAT.BTN"\n',
    "/lib/FORMAT.BTN": "const f = 0\n",
  }, ["/lib"]);
  assertEquals(r.parts, ["FORMAT.BTN", "MAIN.BTN"]);
});

Deno.test("include diagnostics: missing, cycle, position", () => {
  const code = (files: Record<string, string>) =>
    assertThrows(
      () => loadSource("/p/main.btn", { reader: memory(files) }),
      CompileError,
    )
      .code;
  assertEquals(
    code({ "/p/main.btn": 'include "NOPE.BTN"\n' }),
    "include-missing",
  );
  assertEquals(
    code({
      "/p/main.btn": 'include "A.BTN"\n',
      "/p/A.BTN": 'include "MAIN.BTN"\n',
    }),
    "include-cycle",
  );
  const e = assertThrows(
    () =>
      loadSource("/p/main.btn", {
        reader: memory({
          "/p/main.btn": 'const x = 1\ninclude "A.BTN"\n',
          "/p/A.BTN": "",
        }),
      }),
    CompileError,
  );
  assertEquals([e.code, e.position.line], ["include-position", 2]);
});

Deno.test("a part with no final newline still ends its last line", () => {
  const r = show("/p/main.btn", {
    "/p/main.btn": 'include "A.BTN"\nconst m = 0',
    "/p/A.BTN": "const a = 0",
  });
  assertEquals(
    r.tokens.endsWith("0:newline 1:CONST 1:m 1:punct 1:number 1:newline 1:eof"),
    true,
  );
});
