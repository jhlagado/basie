/**
 * Full-fidelity CP/M 2.2: boot the real CCP, BDOS and BIOS on the Triptych
 * machine and drive its console, as Skate's proofs do. Slower than the minimal
 * harness in cpm.ts, so it is used for end-to-end checks.
 */
import { createRequire } from "node:module";
import { join } from "node:path";
import { fromFileUrl } from "@std/path";
// @ts-types="./triptych-tools.d.ts"
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
// @ts-types="./triptych-tools.d.ts"
import {
  createBlankCpm22Disk,
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";

const triptychRoot = fromFileUrl(
  new URL("../../../triptych/", import.meta.url),
);
const require = createRequire(import.meta.url);
// deno-lint-ignore no-explicit-any
const host: any = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);

type Firmware = {
  bootRom: Uint8Array;
  ccp: Uint8Array;
  bdos: Uint8Array;
  bios: Uint8Array;
};

let firmwarePromise: Promise<Firmware> | undefined;

/** Assemble the Triptych firmware once per process. */
function firmware(): Promise<Firmware> {
  firmwarePromise ??= assembleTriptychCpuFirmware(triptychRoot);
  return firmwarePromise;
}

/** A CP/M 2.2 system disk holding the given files. */
export async function systemDisk(files: Record<string, Uint8Array>) {
  const fw = await firmware();
  const system = createBlankCpm22Disk();
  system.set(fw.ccp, 0x0000);
  system.set(fw.bdos, 0x0800);
  system.set(fw.bios, 0x1600);
  let disk: Uint8Array = new Uint8Array(Math.ceil(system.length / 512) * 512);
  disk.set(system);
  for (const [name, bytes] of Object.entries(files)) {
    disk = installCpm22File(disk, { name, bytes, padByte: 0x1a });
  }
  return disk;
}

/** Read a file back from a disk image. */
export function readFile(disk: Uint8Array, name: string): Uint8Array {
  return readCpm22File(disk, name);
}

export type Session = {
  transcript: string;
  /** Type a command and return everything printed up to the next prompt. */
  command(text: string, maxSlices?: number): string;
  /**
   * Run a program interactively: type the command, then type each answer
   * only once the program has printed `ask` again, as a person would. Returns
   * everything printed up to the next CCP prompt. (Type-ahead queued before
   * the program starts loses characters on this machine's CP/M.)
   */
  converse(
    command: string,
    ask: string,
    answers: string[],
    maxSlices?: number,
  ): string;
  /** The current disk image. */
  disk(): Uint8Array;
  close(): void;
};

/** Boot CP/M on a disk and wait for the first prompt. */
export async function boot(disk: Uint8Array): Promise<Session> {
  const fw = await firmware();
  const machine = new host.TriptychCpu(fw.bootRom);
  machine.install_drive(0, disk, true);
  const decoder = new TextDecoder("ascii");
  const encoder = new TextEncoder();
  const session: Session = {
    transcript: "",
    command(text, maxSlices = 8000) {
      const start = session.transcript.length;
      if (!machine.enqueue_serial_input(encoder.encode(`${text}\r`))) {
        throw new Error("Console input queue is full");
      }
      waitForPrompt(start, maxSlices, text);
      const output = session.transcript.slice(start);
      // Drop the echoed command line and the trailing prompt.
      const begin = output.indexOf("\r\n");
      const end = output.lastIndexOf("\r\nA>");
      return output.slice(begin + 2, end >= 0 ? end : output.length);
    },
    converse(command, ask, answers, maxSlices = 40_000) {
      const start = session.transcript.length;
      const type = (text: string) => {
        if (!machine.enqueue_serial_input(encoder.encode(`${text}\r`))) {
          throw new Error("Console input queue is full");
        }
      };
      type(command);
      let seen = start + command.length;
      for (const answer of answers) {
        seen = waitFor(ask, seen, maxSlices, command) + ask.length;
        type(answer);
      }
      waitForPrompt(seen, maxSlices, command);
      const output = session.transcript.slice(start);
      const begin = output.indexOf("\r\n");
      const end = output.lastIndexOf("\r\nA>");
      return output.slice(begin + 2, end >= 0 ? end : output.length);
    },
    disk: () => machine.export_drive(0),
    close: () => machine.free(),
  };
  function waitForPrompt(offset: number, maxSlices: number, what: string) {
    for (let i = 0; i < maxSlices; i += 1) {
      const status = machine.run_slice(50_000, 500_000);
      session.transcript += decoder.decode(machine.take_serial_output());
      if (status === 0) throw new Error(`CP/M halted during ${what}`);
      if (
        session.transcript.length > offset && session.transcript.endsWith("A>")
      ) return;
    }
    throw new Error(
      `Timed out during ${what}: ${
        JSON.stringify(session.transcript.slice(-300))
      }`,
    );
  }
  /** Run until `text` appears at or after `from`; returns where. */
  function waitFor(
    text: string,
    from: number,
    maxSlices: number,
    what: string,
  ) {
    for (let i = 0; i < maxSlices; i += 1) {
      const at = session.transcript.indexOf(text, from);
      if (at >= 0) return at;
      const status = machine.run_slice(50_000, 500_000);
      session.transcript += decoder.decode(machine.take_serial_output());
      if (status === 0) throw new Error(`CP/M halted during ${what}`);
    }
    throw new Error(
      `Timed out waiting for ${JSON.stringify(text)} during ${what}: ${
        JSON.stringify(session.transcript.slice(-300))
      }`,
    );
  }
  waitForPrompt(0, 2000, "boot");
  return session;
}
