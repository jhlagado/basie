/** CRC-16/CCITT-FALSE: polynomial $1021, initial $FFFF, no reflection. */
export function crc16(bytes: Uint8Array, initial = 0xffff): number {
  let crc = initial;
  for (const byte of bytes) {
    crc ^= byte << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}
