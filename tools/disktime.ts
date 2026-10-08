/**
 * A ballpark of how long a build takes on a CP/M machine with mechanical
 * floppy drives: BASIE then BLINK run under the CP/M harness, every BDOS
 * file call logged with the Z80 cycles before it, and the log replayed
 * against a simple drive model. The CPU runs at 4 MHz.
 *
 *   deno task disktime [NAME.BSI ...]
 *
 * The drive model, deliberately simple:
 * - Files present before the build lie contiguously after the directory,
 *   in the order a release disk would hold them; files the build makes
 *   take 1K blocks as they are written, so streams written together
 *   interleave, as CP/M's allocator would place them.
 * - A record on the track the head is on, next in skewed order after the
 *   last, costs the skew's sectors of rotation; any other costs the steps
 *   to its track, the settle, and a rotational latency drawn at random
 *   within one revolution (seeded, so runs repeat), then its sector.
 * - Opening, making, closing, deleting and searching read the directory
 *   track (half the directory on average), and crossing a 16K extent opens
 *   the next one the same way.
 * - The programs themselves are loaded from disk (BASIE.COM, then
 *   BLINK.COM), and CP/M's warm boot reads the system tracks once.
 * Physical sectors larger than a record are read once for all their
 * records (deblocking), and written once when the records move on.
 */
import { basename, dirname } from "@std/path";
import { buildBasie } from "../native/compiler/build.ts";
import {
  assembleFile,
  type BdosCall,
  comBytes,
  runCom,
} from "../tests/harness/cpm.ts";
import { buildRuntime } from "./helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const ROOT = new URL("../", import.meta.url).pathname;
const HZ = 4_000_000;

type Drive = {
  name: string;
  tracks: number;
  sectorsPerTrack: number;
  recordsPerSector: number;
  rpm: number;
  stepMs: number;
  settleMs: number;
  /** Sectors of rotation between consecutive logical sectors (skew). */
  skew: number;
  /** Tracks before the directory (the system tracks). */
  systemTracks: number;
  /** Directory records, read half on average per directory operation. */
  directoryRecords: number;
};

const DRIVES: Drive[] = [
  {
    name: '8" single density (77 x 26 x 128, 360 rpm, skew 6)',
    tracks: 77,
    sectorsPerTrack: 26,
    recordsPerSector: 1,
    rpm: 360,
    stepMs: 8,
    settleMs: 8,
    skew: 6,
    systemTracks: 2,
    directoryRecords: 16,
  },
  {
    name: '5.25" double density (40 x 9 x 512, 300 rpm, skew 2)',
    tracks: 40,
    sectorsPerTrack: 9,
    recordsPerSector: 4,
    rpm: 300,
    stepMs: 6,
    settleMs: 15,
    skew: 2,
    systemTracks: 2,
    directoryRecords: 16,
  },
];

/** A seeded uniform generator in [0, 1). */
function random(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 0x100000000;
  };
}

type Event =
  | { kind: "cpu"; cycles: number }
  | { kind: "dir"; label: string }
  | { kind: "io"; file: string; record: number; write: boolean };

/** Run the build under the harness, logging its disk calls. */
function logged(
  com: Uint8Array,
  tail: string,
  files: Record<string, Uint8Array>,
  events: Event[],
) {
  let last = 0;
  const onBdos = (c: BdosCall) => {
    events.push({ kind: "cpu", cycles: c.cycles - last });
    last = c.cycles;
    if (c.fn >= 15 && c.fn <= 19 || c.fn === 22 || c.fn === 23) {
      events.push({ kind: "dir", label: `${c.fn} ${c.file}` });
    } else if (c.fn === 35) {
      events.push({ kind: "dir", label: `size ${c.file}` });
    } else if (c.record !== undefined && c.file) {
      events.push({
        kind: "io",
        file: c.file,
        record: c.record,
        write: c.fn === 21 || c.fn === 34,
      });
    }
  };
  const run = runCom(com, { tail, files, maxSteps: 2_000_000_000, onBdos });
  events.push({ kind: "cpu", cycles: run.cycles - last });
  return run;
}

/** The time in seconds the events take on a drive, with what they cost. */
function model(
  drive: Drive,
  preexisting: [string, number][],
  events: Event[],
  seed: number,
) {
  const rand = random(seed);
  const rev = 60_000 / drive.rpm; // ms
  const sector = rev / drive.sectorsPerTrack;
  const recordsPerTrack = drive.sectorsPerTrack * drive.recordsPerSector;
  const dataStart = drive.systemTracks * recordsPerTrack +
    drive.directoryRecords;
  // Where each file's records are: a list of disk record numbers.
  const where = new Map<string, number[]>();
  let next = dataStart;
  for (const [name, records] of preexisting) {
    where.set(name, Array.from({ length: records }, (_, i) => next + i));
    next += records;
  }
  let track = drive.systemTracks;
  let lastSector = -1; // physical sector on the head's track, -1 none
  let buffered = -1; // the physical sector deblocked, by disk sector index
  const cost = { cpu: 0, seek: 0, rotate: 0, dir: 0, ovl: 0 };
  const byFile = new Map<string, { records: number; ms: number }>();
  const extents = new Map<string, number>();

  const seekTo = (t: number) => {
    if (t === track) return 0;
    const ms = Math.abs(t - track) * drive.stepMs + drive.settleMs;
    track = t;
    lastSector = -1;
    return ms;
  };
  /** Time to bring physical sector s of the current track under the head. */
  const rotateTo = (s: number) => {
    let ms: number;
    if (lastSector < 0) ms = rand() * rev + sector;
    else {
      // The skewed order: logical successor is `skew` sectors on.
      const gap = (s - lastSector + drive.sectorsPerTrack) %
        drive.sectorsPerTrack;
      ms = (gap === 0 ? drive.sectorsPerTrack : gap) * sector;
    }
    lastSector = s;
    return ms;
  };
  const access = (diskRecord: number) => {
    const physical = Math.floor(diskRecord / drive.recordsPerSector);
    if (physical === buffered) return { seek: 0, rotate: 0 };
    buffered = physical;
    const t = Math.floor(physical / drive.sectorsPerTrack);
    const logical = physical % drive.sectorsPerTrack;
    // Logical sector n sits at physical position n*skew mod spt (skewed).
    const pos = (logical * drive.skew) % drive.sectorsPerTrack +
      Math.floor(logical * drive.skew / drive.sectorsPerTrack);
    const seek = seekTo(t);
    return { seek, rotate: rotateTo(pos % drive.sectorsPerTrack) };
  };
  const directory = () => {
    const seek = seekTo(drive.systemTracks);
    const half = drive.directoryRecords / 2 / drive.recordsPerSector;
    const rotate = rand() * rev + half * drive.skew * sector;
    lastSector = -1;
    buffered = -1;
    return seek + rotate;
  };

  for (const e of events) {
    if (e.kind === "cpu") {
      cost.cpu += e.cycles / HZ * 1000;
    } else if (e.kind === "dir") {
      cost.dir += directory();
    } else {
      let records = where.get(e.file);
      if (!records) where.set(e.file, records = []);
      while (records.length <= e.record) {
        // A new 1K block, eight records, at the next free place.
        for (let i = 0; i < 8; i++) records.push(next++);
      }
      const extent = Math.floor(e.record / 128);
      if ((extents.get(e.file) ?? 0) !== extent) {
        extents.set(e.file, extent);
        cost.dir += directory();
      }
      const { seek, rotate } = access(records[e.record]);
      cost.seek += seek;
      cost.rotate += rotate;
      if (e.file === "BASIE.OVL") cost.ovl += seek + rotate;
      const f = byFile.get(e.file) ?? { records: 0, ms: 0 };
      f.records += 1;
      f.ms += seek + rotate;
      byFile.set(e.file, f);
    }
  }
  return { ...cost, byFile };
}

/** The records a program file takes. */
const recs = (b: Uint8Array) => Math.ceil(b.length / 128);

async function main() {
  const names = Deno.args.length > 0 ? Deno.args : [
    `${ROOT}examples/ADVENT.BSI`,
    `${ROOT}tests/native/programs/BIGMAIN.BSI`,
  ];
  const basie = await buildBasie();
  const blink = comBytes(
    await assembleFile(`${ROOT}native/linker/BLINK.ASM`, ROOT),
  );
  const lib = (await buildRuntime()).file;
  const msg = messageFile();
  for (const path of names) {
    const name = basename(path).replace(/\.BSI$/i, "");
    const parts: Record<string, Uint8Array> = {};
    for (const dir of [`${ROOT}lib`, dirname(path)]) {
      for (const f of Deno.readDirSync(dir)) {
        if (/^[A-Z0-9]{1,8}\.BSI$/.test(f.name)) {
          parts[f.name] = Deno.readFileSync(`${dir}/${f.name}`);
        }
      }
    }
    const disk: Record<string, Uint8Array> = {
      "BASIE.COM": basie.com,
      "BASIE.OVL": basie.ovl,
      "BASIE.MSG": msg,
      "BLINK.COM": blink,
      "CPM22.BRL": lib,
      ...parts,
    };
    const events: Event[] = [];
    // CP/M loads BASIE.COM: a directory search, then its records.
    const load = (file: string, b: Uint8Array) => {
      events.push({ kind: "dir", label: `load ${file}` });
      for (let r = 0; r < recs(b); r++) {
        events.push({ kind: "io", file, record: r, write: false });
      }
    };
    load("BASIE.COM", basie.com);
    const compiled = logged(basie.com, `${name} [C]`, disk, events);
    if (compiled.output) throw new Error(`${name}: ${compiled.output}`);
    const compileEvents = events.length;
    // The chain: CP/M loads BLINK.COM, which links the streams.
    load("BLINK.COM", blink);
    const files: Record<string, Uint8Array> = { ...disk };
    for (const [k, v] of compiled.disk) files[k] = v;
    const linked = logged(blink, name, files, events);
    if (linked.output) throw new Error(`${name} link: ${linked.output}`);
    const source = Object.entries(parts).filter(([k]) =>
      events.some((e) => e.kind === "io" && e.file === k)
    ).reduce((a, [, v]) => a + v.length, 0);
    const ovlRecords = events.filter((e) =>
      e.kind === "io" && e.file === "BASIE.OVL"
    ).length;
    let ovlLoads = 0;
    let prev = -2;
    for (const e of events) {
      if (e.kind !== "io" || e.file !== "BASIE.OVL") continue;
      if (e.record !== prev + 1) ovlLoads += 1;
      prev = e.record;
    }
    console.log(
      `\n${name}: ${source} bytes of source read; BASIE.OVL ${ovlRecords} ` +
        `records read in ${ovlLoads} loads`,
    );
    const preexisting: [string, number][] = Object.entries(disk).map((
      [k, v],
    ) => [k, recs(v)]);
    for (const drive of DRIVES) {
      const trials = [1, 2, 3, 4, 5].map((seed) =>
        model(drive, preexisting, events, seed)
      );
      const avg = (k: "cpu" | "seek" | "rotate" | "dir" | "ovl") =>
        trials.reduce((a, t) => a + t[k], 0) / trials.length / 1000;
      const compileCpu = events.slice(0, compileEvents).reduce(
        (a, e) => a + (e.kind === "cpu" ? e.cycles : 0),
        0,
      ) / HZ;
      const total = avg("cpu") + avg("seek") + avg("rotate") + avg("dir");
      console.log(
        `  ${drive.name}:\n` +
          `    CPU ${avg("cpu").toFixed(1)} s (compiling ${
            compileCpu.toFixed(1)
          } s), disk ${
            (avg("seek") + avg("rotate") + avg("dir")).toFixed(1)
          } s (seeks ${avg("seek").toFixed(1)}, rotation ${
            avg("rotate").toFixed(1)
          }, directory ${avg("dir").toFixed(1)}); overlays ${
            avg("ovl").toFixed(1)
          } s; total ${total.toFixed(1)} s`,
      );
      const rows = [...trials[0].byFile].sort((a, b) => b[1].ms - a[1].ms)
        .slice(0, 8).map(([k, v]) =>
          `${k} ${v.records} rec ${(v.ms / 1000).toFixed(1)} s`
        );
      console.log(`    by file: ${rows.join("; ")}`);
    }
  }
}

if (import.meta.main) await main();
