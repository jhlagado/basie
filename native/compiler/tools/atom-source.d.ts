export function assembleAtomSource(
  entry: string,
  options?: Record<string, unknown>,
): Promise<{
  hex: string;
  symbols: Record<string, number>;
  addresses: Record<string, number>;
}>;
