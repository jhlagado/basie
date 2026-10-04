/**
 * The runtime's helper table, version 1: the ordinal and calling convention
 * of every helper and service in CPM22.BRL (object format §10). The
 * compiler carries this table; a test checks it against the runtime source.
 *
 * Conventions: 1 = a service with a Baton signature, called with arguments
 * on the stack; 2 = a register helper.
 */

export const HELPER_VERSION = 1;

export type HelperEntry = {
  name: string;
  ordinal: number;
  convention: 1 | 2;
  /** For services: the Baton signature, parsed by the compiler. */
  signature?: string;
  /** Stack bytes the helper itself uses beyond its arguments. */
  stack: number;
};

export const Helper = {
  STARTUP: 0x001,
  EXIT: 0x002,
  TRAP: 0x005,
  CONOUT: 0x007,
  TRAP_BOUNDS: 0x008,
  RETN: 0x009,
  STKCHK: 0x00a,
  TRAP_NARROWING: 0x00b,
  TRAP_DIVISION: 0x00c,
  TRAP_FLOAT_OVERFLOW: 0x00d,
  TRAP_FLOAT_INVALID: 0x00e,
  TRAP_LOOP_RANGE: 0x00f,
  TRAP_ACTIVATION: 0x010,
  TRAP_STALE: 0x011,
  TRAP_CYCLE: 0x012,
  TRAP_POOL_FULL: 0x013,
  TRAP_ASSERTION: 0x014,
  PUTDEC: 0x015,
} as const;

export const TRAP_REPORTERS: Record<string, number> = {
  bounds: Helper.TRAP_BOUNDS,
  narrowing: Helper.TRAP_NARROWING,
  "division-by-zero": Helper.TRAP_DIVISION,
  "float-overflow": Helper.TRAP_FLOAT_OVERFLOW,
  "float-invalid": Helper.TRAP_FLOAT_INVALID,
  "loop-range": Helper.TRAP_LOOP_RANGE,
  "activation-capacity": Helper.TRAP_ACTIVATION,
  "stale-handle": Helper.TRAP_STALE,
  "ownership-cycle": Helper.TRAP_CYCLE,
  "pool-full": Helper.TRAP_POOL_FULL,
  assertion: Helper.TRAP_ASSERTION,
};

/** Services, with the signatures the compiler predeclares (services.md). */
export const SERVICES: HelperEntry[] = [
  {
    name: "writeText",
    ordinal: 0x020,
    convention: 1,
    signature: "sub writeText(f as File, s as string[]) fails",
    stack: 8,
  },
  {
    name: "writeByte",
    ordinal: 0x021,
    convention: 1,
    signature: "sub writeByte(f as File, b as u8) fails",
    stack: 8,
  },
];

export const NUCLEUS_SHORTHANDS: HelperEntry[] = [
  {
    name: "writeOutputByte",
    ordinal: 0x022,
    convention: 1,
    signature: "sub writeOutputByte(b as u8) fails",
    stack: 8,
  },
];
SERVICES.push(...NUCLEUS_SHORTHANDS);

export const REGISTER_HELPERS: HelperEntry[] = [
  { name: "RETN", ordinal: Helper.RETN, convention: 2, stack: 4 },
  { name: "STKCHK", ordinal: Helper.STKCHK, convention: 2, stack: 2 },
  { name: "CONOUT", ordinal: Helper.CONOUT, convention: 2, stack: 8 },
];

/** Predeclared constants (spec §16.2). */
export const PREDECLARED_CONSTANTS: [string, number][] = [
  ["endOfInput", 1],
  ["endOfFile", 1],
  ["inputFailure", 2],
  ["outputFailure", 3],
  ["storageFailure", 4],
  ["fileNotFound", 5],
  ["fileExists", 6],
  ["badName", 7],
  ["tooManyFiles", 8],
  ["fileClosed", 9],
  ["diskFull", 10],
  ["directoryFull", 11],
  ["readOnly", 12],
  ["seekFailure", 13],
  ["lineTooLong", 14],
  ["notAvailable", 15],
  ["fileBusy", 16],
  ["noSearch", 17],
  ["badMode", 18],
  ["invalid", 254],
];

/** The fixed File values the runtime recognises before consulting its table. */
export const CONSOLE_FILE = 1;
export const PRINTER_FILE = 2;
