/** Compile-time diagnostics (docs/diagnostics.md). */
import type { Position } from "./lexer.ts";

export class CompileError extends Error {
  constructor(
    public readonly code: string,
    public readonly position: Position,
    message: string,
  ) {
    super(`${code} at ${position.line}:${position.column}: ${message}`);
  }
}

export const fail = (
  code: string,
  position: Position,
  message: string,
): never => {
  throw new CompileError(code, position, message);
};
