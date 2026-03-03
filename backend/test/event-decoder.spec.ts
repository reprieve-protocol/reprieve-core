import { decodeIndexedEvent } from '../src/modules/rescue-history/event-decoder';
import { EVENT_TOPICS } from '../src/modules/rescue-history/event-topics';
import { RawRpcLog } from '../src/modules/rescue-history/types';

const padWord = (hexNoPrefix: string): string => hexNoPrefix.padStart(64, '0');
const uintWord = (value: bigint): string => value.toString(16).padStart(64, '0');
const addrTopic = (address: string): string =>
  `0x${'0'.repeat(24)}${address.replace(/^0x/, '').toLowerCase()}`;

describe('rescue-history event decoder', () => {
  it('decodes PositionUpdated', () => {
    const user = '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5';
    const data = `0x${uintWord(22000000000000000000n)}${uintWord(16000000000n)}${uintWord(1100000000000000000n)}`;

    const log: RawRpcLog = {
      address: '0x1111111111111111111111111111111111111111',
      blockNumber: '0x10',
      transactionHash: `0x${'a'.repeat(64)}`,
      logIndex: '0x1',
      topics: [EVENT_TOPICS.PositionUpdated, addrTopic(user)],
      data,
    };

    const decoded = decodeIndexedEvent(log);
    expect(decoded?.eventName).toBe('PositionUpdated');
    expect(decoded?.userAddress).toBe(user.toLowerCase());
    expect(decoded?.payload.collateral).toBe('22000000000000000000');
    expect(decoded?.payload.debt).toBe('16000000000');
    expect(decoded?.payload.hfWad).toBe('1100000000000000000');
  });

  it('decodes RescueInitiated', () => {
    const execId = `0x${'a'.repeat(64)}`;
    const user = '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5';

    const data = `0x${uintWord(1n)}${uintWord(1772522004n)}`;

    const log: RawRpcLog = {
      address: '0x1111111111111111111111111111111111111111',
      blockNumber: '0x10',
      transactionHash: `0x${'b'.repeat(64)}`,
      logIndex: '0x1',
      topics: [EVENT_TOPICS.RescueInitiated, execId, addrTopic(user)],
      data,
    };

    const decoded = decodeIndexedEvent(log);
    expect(decoded?.eventName).toBe('RescueInitiated');
    expect(decoded?.execId).toBe(execId);
    expect(decoded?.userAddress).toBe(user.toLowerCase());
    expect(decoded?.payload.steps).toBe('1');
    expect(decoded?.payload.deadline).toBe('1772522004');
  });

  it('decodes LogEntryAdded with details string', () => {
    const execId = `0x${'c'.repeat(64)}`;
    const stepIndex = 3n;
    const user = '0x1234000000000000000000000000000000000000';
    const details = 'Step 3 completed [mode=TOP_UP]';

    const detailsHex = Buffer.from(details, 'utf8').toString('hex');
    const detailsPadded = detailsHex.padEnd(Math.ceil(detailsHex.length / 64) * 64, '0');

    const data =
      `0x${uintWord(1n)}` +
      `${uintWord(64n)}` +
      `${uintWord(BigInt(details.length))}` +
      `${detailsPadded}`;

    const log: RawRpcLog = {
      address: '0x2222222222222222222222222222222222222222',
      blockNumber: '0x20',
      transactionHash: `0x${'d'.repeat(64)}`,
      logIndex: '0x2',
      topics: [
        EVENT_TOPICS.LogEntryAdded,
        execId,
        `0x${padWord(stepIndex.toString(16))}`,
        addrTopic(user),
      ],
      data,
    };

    const decoded = decodeIndexedEvent(log);
    expect(decoded?.eventName).toBe('LogEntryAdded');
    expect(decoded?.execId).toBe(execId);
    expect(decoded?.userAddress).toBe(user.toLowerCase());
    expect(decoded?.payload.stepIndex).toBe(stepIndex.toString());
    expect(decoded?.payload.details).toBe(details);
  });
});
