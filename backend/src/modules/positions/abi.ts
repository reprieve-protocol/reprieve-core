// discoverPositions(address)
export const DISCOVER_POSITIONS_SELECTOR = '0x97c6c37f';

const strip0x = (value: string): string =>
  value.startsWith('0x') ? value.slice(2) : value;

const pad32 = (hexNoPrefix: string): string => hexNoPrefix.padStart(64, '0');

const chunkWords = (hexNoPrefix: string): string[] => {
  if (hexNoPrefix.length % 64 !== 0) {
    throw new Error('Invalid ABI payload length');
  }

  const words: string[] = [];
  for (let i = 0; i < hexNoPrefix.length; i += 64) {
    words.push(hexNoPrefix.slice(i, i + 64));
  }
  return words;
};

const readWordAsBigInt = (words: string[], index: number): bigint => {
  if (index < 0 || index >= words.length) {
    throw new Error('ABI decode out of bounds');
  }
  return BigInt(`0x${words[index]}`);
};

const readWordAsAddress = (words: string[], index: number): string => {
  const word = words[index];
  if (!word) {
    throw new Error('ABI decode address out of bounds');
  }
  return `0x${word.slice(24)}`;
};

export const encodeDiscoverPositionsCalldata = (userAddress: string): string => {
  const user = strip0x(userAddress).toLowerCase();
  if (user.length !== 40) {
    throw new Error(`Invalid user address: ${userAddress}`);
  }

  return `${DISCOVER_POSITIONS_SELECTOR}${pad32(user)}`;
};

export interface DecodedDiscoverPosition {
  protocol: string;
  collateralAsset: string;
  debtAsset: string;
  collateralAmount: string;
  debtAmount: string;
  healthFactor: string;
  ltvBps: string;
  maxLtvBps: string;
  liquidationThresholdBps: string;
}

export const decodeDiscoverPositionsResult = (
  returnData: string,
): DecodedDiscoverPosition[] => {
  const data = strip0x(returnData);

  if (data.length === 0) {
    return [];
  }

  const words = chunkWords(data);
  const arrayOffsetBytes = Number(readWordAsBigInt(words, 0));
  const arrayOffsetWords = Math.floor(arrayOffsetBytes / 32);

  const length = Number(readWordAsBigInt(words, arrayOffsetWords));
  const tupleWords = 9;

  const results: DecodedDiscoverPosition[] = [];
  for (let i = 0; i < length; i += 1) {
    const base = arrayOffsetWords + 1 + i * tupleWords;

    results.push({
      protocol: readWordAsAddress(words, base + 0),
      collateralAsset: readWordAsAddress(words, base + 1),
      debtAsset: readWordAsAddress(words, base + 2),
      collateralAmount: readWordAsBigInt(words, base + 3).toString(),
      debtAmount: readWordAsBigInt(words, base + 4).toString(),
      healthFactor: readWordAsBigInt(words, base + 5).toString(),
      ltvBps: readWordAsBigInt(words, base + 6).toString(),
      maxLtvBps: readWordAsBigInt(words, base + 7).toString(),
      liquidationThresholdBps: readWordAsBigInt(words, base + 8).toString(),
    });
  }

  return results;
};
