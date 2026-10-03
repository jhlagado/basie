/**
 * The reference compiler's entry point. Until a source construct is
 * implemented, compile() throws NotImplemented, and the conformance runner
 * reports the test as pending.
 */

export class NotImplemented extends Error {}

export type Diagnostic = {
  code: string;
  line: number;
  column: number;
  message: string;
};

export type CompileResult =
  | { ok: true; com: Uint8Array; lines?: Uint8Array }
  | { ok: false; diagnostics: Diagnostic[] }
  | { ok: false; linkError: string };

/** Compile and link one Baton program to a .COM image. */
export function compile(_path: string, _source: string): CompileResult {
  throw new NotImplemented("the reference compiler is not written yet");
}
