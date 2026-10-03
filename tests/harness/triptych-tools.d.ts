export function assembleTriptychCpuFirmware(root: string): Promise<{
  bootRom: Uint8Array;
  ccp: Uint8Array;
  bdos: Uint8Array;
  bios: Uint8Array;
}>;
export function createBlankCpm22Disk(): Uint8Array;
export function installCpm22File(
  disk: Uint8Array,
  file: { name: string; bytes: Uint8Array; padByte: number },
): Uint8Array;
export function readCpm22File(disk: Uint8Array, name: string): Uint8Array;
