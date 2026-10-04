import { assertEquals } from "@std/assert";
import { MemoryDisk } from "../ref/toolchain/disk.ts";
import { abandon, publish } from "../ref/toolchain/publish.ts";

const b = (...xs: number[]) => new Uint8Array(xs);
const opts = { output: "HELLO", spool: "HELLO" };
const names = (d: MemoryDisk) => [...d.files.keys()].sort();

Deno.test("publish keeps the old program as .BAK and removes intermediates", () => {
  const disk = new MemoryDisk({
    "HELLO.COM": b(1),
    "HELLO.BAK": b(0),
    "HELLO.LIN": b(9),
    "HELLO.$DR": b(),
    "HELLO.$BY": b(),
  });
  const r = publish(disk, {
    kind: "COM",
    image: b(2),
    lineTable: b(3),
    map: "M",
  }, opts);
  assertEquals(r, { published: true, messages: [] });
  assertEquals(names(disk), [
    "HELLO.BAK",
    "HELLO.COM",
    "HELLO.LIN",
    "HELLO.MAP",
  ]);
  assertEquals(disk.read("HELLO.BAK"), b(1));
  assertEquals(disk.read("HELLO.COM"), b(2));
  assertEquals(disk.read("HELLO.LIN"), b(3));
});

Deno.test("option Z keeps no backup; option K keeps intermediates", () => {
  const disk = new MemoryDisk({ "HELLO.COM": b(1), "HELLO.$DR": b() });
  publish(disk, { kind: "COM", image: b(2) }, {
    ...opts,
    noBackup: true,
    keepIntermediates: true,
  });
  assertEquals(names(disk), ["HELLO.$DR", "HELLO.COM"]);
});

Deno.test("a leftover temporary from a crashed build is replaced, not duplicated", () => {
  const disk = new MemoryDisk({ "HELLO.$$$": b(7), "HELLO.$LT": b(7) });
  publish(disk, { kind: "COM", image: b(2), lineTable: b(3) }, opts);
  assertEquals(names(disk), ["HELLO.COM", "HELLO.LIN"]);
});

Deno.test("a disk full before publication leaves the outputs untouched", () => {
  const disk = new MemoryDisk({
    "HELLO.COM": b(1),
    "HELLO.LIN": b(9),
    "HELLO.$DR": b(),
  });
  disk.capacity = 2;
  const r = publish(
    disk,
    { kind: "COM", image: b(2), lineTable: b(3, 4, 5) },
    opts,
  );
  assertEquals(r, { published: false, messages: ["HELLO.$LT: disk full"] });
  assertEquals(names(disk), ["HELLO.COM", "HELLO.LIN"]);
  assertEquals(disk.read("HELLO.COM"), b(1));
});

Deno.test("a write error on a report after publication deletes only the report", () => {
  const disk = new MemoryDisk();
  disk.faults = [{ name: "HELLO.MAP", condition: "write error" }];
  const r = publish(disk, {
    kind: "COM",
    image: b(2),
    map: "M",
    symbols: b(0x1a),
  }, opts);
  assertEquals(r, { published: true, messages: ["HELLO.MAP: write error"] });
  assertEquals(names(disk), ["HELLO.COM", "HELLO.SYM"]);
});

Deno.test("a build without a line table removes a stale one", () => {
  const disk = new MemoryDisk({ "HELLO.COM": b(1), "HELLO.LIN": b(9) });
  publish(disk, { kind: "COM", image: b(2) }, { ...opts, noBackup: true });
  assertEquals(names(disk), ["HELLO.COM"]);
});

Deno.test("abandon after a link error removes temporaries only", () => {
  const disk = new MemoryDisk({
    "HELLO.COM": b(1),
    "HELLO.$$$": b(),
    "HELLO.$LT": b(),
    "HELLO.$DR": b(),
    "HELLO.$NM": b(),
  });
  abandon(disk, opts);
  assertEquals(names(disk), ["HELLO.COM"]);
});
