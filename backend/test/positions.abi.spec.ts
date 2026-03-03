import {
  decodeDiscoverPositionsResult,
  encodeDiscoverPositionsCalldata,
} from '../src/modules/positions/abi';

const padWord = (hex: string): string => hex.replace(/^0x/, '').padStart(64, '0');
const encodeAddressWord = (address: string): string =>
  padWord(address.replace(/^0x/, '').toLowerCase());
const encodeUintWord = (value: bigint): string =>
  value.toString(16).padStart(64, '0');

describe('positions abi helpers', () => {
  it('encodes discoverPositions calldata', () => {
    const calldata = encodeDiscoverPositionsCalldata(
      '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
    );

    expect(calldata.startsWith('0x97c6c37f')).toBe(true);
    expect(calldata).toHaveLength(10 + 64);
  });

  it('decodes discoverPositions result with one position', () => {
    const protocol = '0x1111111111111111111111111111111111111111';
    const collateral = '0x2222222222222222222222222222222222222222';
    const debt = '0x3333333333333333333333333333333333333333';

    const words = [
      encodeUintWord(32n),
      encodeUintWord(1n),
      encodeAddressWord(protocol),
      encodeAddressWord(collateral),
      encodeAddressWord(debt),
      encodeUintWord(1000n),
      encodeUintWord(500n),
      encodeUintWord(1_800_000_000_000_000_000n),
      encodeUintWord(7500n),
      encodeUintWord(8000n),
      encodeUintWord(8500n),
    ];

    const encoded = `0x${words.join('')}`;
    const decoded = decodeDiscoverPositionsResult(encoded);

    expect(decoded).toHaveLength(1);
    expect(decoded[0].protocol).toBe(protocol.toLowerCase());
    expect(decoded[0].collateralAsset).toBe(collateral.toLowerCase());
    expect(decoded[0].debtAsset).toBe(debt.toLowerCase());
    expect(decoded[0].collateralAmount).toBe('1000');
    expect(decoded[0].debtAmount).toBe('500');
    expect(decoded[0].healthFactor).toBe('1800000000000000000');
    expect(decoded[0].ltvBps).toBe('7500');
    expect(decoded[0].maxLtvBps).toBe('8000');
    expect(decoded[0].liquidationThresholdBps).toBe('8500');
  });
});
