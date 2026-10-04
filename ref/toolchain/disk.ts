/**
 * A CP/M-like disk for the reference toolchain: flat 8.3 names, no rename
 * over an existing name, and injectable failures for testing (toolchain §6).
 */

export type DiskCondition =
  | "disk full"
  | "directory full"
  | "write error"
  | "read error";

export class DiskError extends Error {
  constructor(
    public readonly file: string,
    public readonly condition: DiskCondition,
  ) {
    super(`${file}: ${condition}`);
  }
}

export interface Disk {
  exists(name: string): boolean;
  read(name: string): Uint8Array;
  write(name: string, bytes: Uint8Array): void;
  delete(name: string): void;
  rename(from: string, to: string): void;
}

export type Fault = { name: string; condition: DiskCondition };

/** An in-memory disk. `faults` fail the first write or read of a name. */
export class MemoryDisk implements Disk {
  readonly files = new Map<string, Uint8Array>();
  faults: Fault[] = [];
  /** Bytes left before the disk is full; Infinity by default. */
  capacity = Infinity;

  constructor(files: Record<string, Uint8Array> = {}) {
    for (const [k, v] of Object.entries(files)) {
      this.files.set(k.toUpperCase(), v);
    }
  }

  private fault(name: string, read: boolean): void {
    const i = this.faults.findIndex((f) =>
      f.name === name && (f.condition === "read error") === read
    );
    if (i >= 0) {
      const [f] = this.faults.splice(i, 1);
      throw new DiskError(name, f.condition);
    }
  }

  exists(name: string): boolean {
    return this.files.has(name.toUpperCase());
  }

  read(name: string): Uint8Array {
    name = name.toUpperCase();
    this.fault(name, true);
    const f = this.files.get(name);
    if (!f) throw new DiskError(name, "read error");
    return f;
  }

  write(name: string, bytes: Uint8Array): void {
    name = name.toUpperCase();
    // CP/M's make-file doesn't check for an existing name; the toolchain must.
    if (this.files.has(name)) {
      throw new Error(`duplicate directory entry ${name}`);
    }
    this.fault(name, false);
    if (bytes.length > this.capacity) {
      // A partly written file stays in the directory, as on CP/M.
      this.files.set(name, bytes.slice(0, this.capacity));
      this.capacity = 0;
      throw new DiskError(name, "disk full");
    }
    this.capacity -= bytes.length;
    this.files.set(name, bytes);
  }

  delete(name: string): void {
    name = name.toUpperCase();
    const f = this.files.get(name);
    if (f) this.capacity += f.length;
    this.files.delete(name);
  }

  rename(from: string, to: string): void {
    from = from.toUpperCase();
    to = to.toUpperCase();
    if (this.files.has(to)) throw new Error(`rename over existing ${to}`);
    const f = this.files.get(from);
    if (!f) throw new DiskError(from, "read error");
    this.files.delete(from);
    this.files.set(to, f);
  }
}
