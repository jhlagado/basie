/**
 * What the compiler knows of the runtime's helpers (object format §10). The
 * ordinals, conventions and stack figures come from the generated helper
 * table (helper-table.ts, from the runtime source); this module names the
 * helpers the code generator calls and gives each service its Basie
 * signature. A test checks the two agree.
 *
 * Conventions: 1 = a service with a Basie signature, called with arguments
 * on the stack; 2 = a register helper.
 */
import { HELPER_KEYS, HELPER_TABLE, HELPER_VERSION } from "./helper-table.ts";

export { HELPER_KEYS, HELPER_TABLE, HELPER_VERSION };

/** The interface key of the helper-table version the compiler is built for. */
export const HELPER_KEY = HELPER_KEYS[HELPER_VERSION - 1];

const FIGURES = new Map(HELPER_TABLE.map((h) => [h.ordinal, h]));

/** The stack figure of a helper: bytes a returning call uses. */
export function helperStack(ordinal: number): number {
  const h = FIGURES.get(ordinal);
  if (!h) throw new Error(`no helper at ordinal ${ordinal}`);
  return h.stack;
}

export type ServiceEntry = {
  name: string;
  ordinal: number;
  /** The Basie signature, parsed by the compiler. */
  signature: string;
  /** Stack bytes a returning call uses (the helper table's figure). */
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

/** [ordinal, signature] for every service (services.md). */
const SERVICE_SIGNATURES: [number, string][] = [
  [0x020, "sub writeText(f as File, s as string[]) fails"],
  [0x021, "sub writeByte(f as File, b as u8) fails"],
  [0x022, "sub writeOutputByte(b as u8) fails"],
  [0x06d, "sub readByte(f as File) as u8 fails"],
  [0x06e, "sub readInputByte() as u8 fails"],
  [0x06f, "sub readKey() as u8"],
  [0x070, "sub keyReady() as boolean"],
  [0x071, "sub readLine(f as File, var line as string[]) fails"],
  [0x072, "sub openRead(name as string[], mode as u8) as File fails"],
  [0x073, "sub openWrite(name as string[], mode as u8) as File fails"],
  [0x074, "sub openAppend(name as string[], mode as u8) as File fails"],
  [0x075, "sub openUpdate(name as string[]) as File fails"],
  [0x076, "sub close(f as File) fails"],
  [0x077, "sub abort(f as File)"],
  [0x078, "sub flush(f as File) fails"],
  [
    0x079,
    "sub readBlock(f as File, var buf as u8[], count as u16) as u16 fails",
  ],
  [0x07a, "sub writeBlock(f as File, buf as u8[], count as u16) fails"],
  [0x07b, "sub seek(f as File, position as u32) fails"],
  [0x07c, "sub position(f as File) as u32 fails"],
  [0x07d, "sub size(f as File) as u32 fails"],
  [0x07e, "sub exists(name as string[]) as boolean fails"],
  [0x07f, "sub delete(name as string[]) fails"],
  [0x080, "sub rename(oldName as string[], newName as string[]) fails"],
  [
    0x081,
    "sub findFirst(pattern as string[], var name as string[]) as boolean fails",
  ],
  [0x082, "sub findNext(var name as string[]) as boolean fails"],
  [0x084, "sub commandTail(var text as string[])"],
  [0x085, "sub resetDisks()"],
  [0x086, "sub resetDrive(drive as u8)"],
  [0x087, "sub currentDrive() as u8"],
  [0x088, "sub selectDrive(drive as u8) fails"],
  [0x089, "sub currentUser() as u8"],
  [0x08a, "sub setUser(user as u8) fails"],
  [0x08b, "sub driveReadOnly(drive as u8) as boolean"],
  [0x08c, "sub freeMemory() as u16"],
];

/** Services, with the signatures the compiler predeclares (services.md). */
export const SERVICES: ServiceEntry[] = SERVICE_SIGNATURES.map((
  [ordinal, signature],
) => ({
  name: signature.match(/^sub (\w+)/)![1],
  ordinal,
  signature,
  stack: helperStack(ordinal),
}));
/** The console shorthands (spec §16.2). */
export const CONSOLE_SHORTHANDS = SERVICES.filter((x) =>
  x.name === "writeOutputByte" || x.name === "readInputByte"
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
  ["textMode", 0],
  ["binaryMode", 1],
];

/** The fixed File values the runtime recognises before consulting its table. */
export const CONSOLE_FILE = 1;
export const PRINTER_FILE = 2;
