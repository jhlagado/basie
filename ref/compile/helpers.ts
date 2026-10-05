/**
 * The runtime's helper table, version 1: the ordinal and calling convention
 * of every helper and service in CPM22.BRL (object format §10). The
 * compiler carries this table; a test checks it against the runtime source.
 *
 * Conventions: 1 = a service with a Basie signature, called with arguments
 * on the stack; 2 = a register helper.
 */

export const HELPER_VERSION = 1;

export type HelperEntry = {
  name: string;
  ordinal: number;
  convention: 1 | 2;
  /** For services: the Basie signature, parsed by the compiler. */
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
  MUL16: 0x016,
  DIV16: 0x017,
  DIV16S: 0x018,
  STR_SETL: 0x019,
  POOL_TRY: 0x01b,
  POOL_DEL: 0x01c,
  OBJ_FREE: 0x01d,
  ID_CHK: 0x01e,
  ID_TEST: 0x01f,
  OWN_SET: 0x023,
  OWN_SETC: 0x024,
  LINK0: 0x025,
  ID_MAKE: 0x026,
  ADD32: 0x028,
  SUB32: 0x029,
  CMP32U: 0x02a,
  CMP32S: 0x02b,
  NEG32: 0x02c,
  MUL32: 0x02d,
  DIV32U: 0x02e,
  DIV32S: 0x02f,
  AND32: 0x030,
  OR32: 0x031,
  XOR32: 0x032,
  SHL32: 0x033,
  SHR32U: 0x034,
  SHR32S: 0x035,
  FADD: 0x03a,
  FSUB: 0x03b,
  FMUL: 0x03c,
  FDIV: 0x03d,
  FCMP: 0x03e,
  I2F: 0x03f,
  U2F: 0x040,
  F2I: 0x041,
  F2U: 0x042,
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
  { name: "MUL16", ordinal: Helper.MUL16, convention: 2, stack: 2 },
  { name: "DIV16", ordinal: Helper.DIV16, convention: 2, stack: 2 },
  { name: "DIV16S", ordinal: Helper.DIV16S, convention: 2, stack: 8 },
  { name: "STR_SETL", ordinal: Helper.STR_SETL, convention: 2, stack: 4 },
  { name: "POOL_TRY", ordinal: Helper.POOL_TRY, convention: 2, stack: 10 },
  { name: "POOL_DEL", ordinal: Helper.POOL_DEL, convention: 2, stack: 8 },
  { name: "OBJ_FREE", ordinal: Helper.OBJ_FREE, convention: 2, stack: 12 },
  { name: "ID_CHK", ordinal: Helper.ID_CHK, convention: 2, stack: 4 },
  { name: "ID_TEST", ordinal: Helper.ID_TEST, convention: 2, stack: 4 },
  { name: "OWN_SET", ordinal: Helper.OWN_SET, convention: 2, stack: 14 },
  { name: "OWN_SETC", ordinal: Helper.OWN_SETC, convention: 2, stack: 16 },
  { name: "LINK0", ordinal: Helper.LINK0, convention: 2, stack: 4 },
  { name: "ID_MAKE", ordinal: Helper.ID_MAKE, convention: 2, stack: 4 },
  { name: "ADD32", ordinal: Helper.ADD32, convention: 2, stack: 6 },
  { name: "SUB32", ordinal: Helper.SUB32, convention: 2, stack: 6 },
  { name: "CMP32U", ordinal: Helper.CMP32U, convention: 2, stack: 8 },
  { name: "CMP32S", ordinal: Helper.CMP32S, convention: 2, stack: 8 },
  { name: "NEG32", ordinal: Helper.NEG32, convention: 2, stack: 2 },
  { name: "MUL32", ordinal: Helper.MUL32, convention: 2, stack: 4 },
  { name: "DIV32U", ordinal: Helper.DIV32U, convention: 2, stack: 4 },
  { name: "DIV32S", ordinal: Helper.DIV32S, convention: 2, stack: 10 },
  { name: "AND32", ordinal: Helper.AND32, convention: 2, stack: 6 },
  { name: "OR32", ordinal: Helper.OR32, convention: 2, stack: 6 },
  { name: "XOR32", ordinal: Helper.XOR32, convention: 2, stack: 6 },
  { name: "SHL32", ordinal: Helper.SHL32, convention: 2, stack: 2 },
  { name: "SHR32U", ordinal: Helper.SHR32U, convention: 2, stack: 2 },
  { name: "SHR32S", ordinal: Helper.SHR32S, convention: 2, stack: 2 },
  { name: "FADD", ordinal: Helper.FADD, convention: 2, stack: 12 },
  { name: "FSUB", ordinal: Helper.FSUB, convention: 2, stack: 12 },
  { name: "FMUL", ordinal: Helper.FMUL, convention: 2, stack: 12 },
  { name: "FDIV", ordinal: Helper.FDIV, convention: 2, stack: 12 },
  { name: "FCMP", ordinal: Helper.FCMP, convention: 2, stack: 10 },
  { name: "I2F", ordinal: Helper.I2F, convention: 2, stack: 8 },
  { name: "U2F", ordinal: Helper.U2F, convention: 2, stack: 8 },
  { name: "F2I", ordinal: Helper.F2I, convention: 2, stack: 6 },
  { name: "F2U", ordinal: Helper.F2U, convention: 2, stack: 6 },
];

export const HELPER_STACK: Record<number, number> = Object.fromEntries(
  REGISTER_HELPERS.map((h) => [h.ordinal, h.stack]),
);

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
