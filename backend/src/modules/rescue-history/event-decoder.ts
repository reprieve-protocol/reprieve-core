import { EVENT_TOPICS } from './event-topics';
import { DecodedRescueEvent, RawRpcLog } from './types';

const strip0x = (value: string): string =>
  value.startsWith('0x') ? value.slice(2) : value;

const readWord = (dataNo0x: string, index: number): string => {
  const start = index * 64;
  const end = start + 64;
  if (end > dataNo0x.length) {
    throw new Error('Data word out of bounds');
  }
  return dataNo0x.slice(start, end);
};

const topicToAddress = (topic: string): string =>
  `0x${strip0x(topic).slice(24)}`.toLowerCase();

const wordToBigInt = (word: string): bigint => BigInt(`0x${word}`);

const readAddressWord = (dataNo0x: string, index: number): string =>
  `0x${readWord(dataNo0x, index).slice(24)}`.toLowerCase();

const readUintWord = (dataNo0x: string, index: number): string =>
  wordToBigInt(readWord(dataNo0x, index)).toString();

const readBytes32Word = (dataNo0x: string, index: number): string =>
  `0x${readWord(dataNo0x, index)}`.toLowerCase();

const decodeStringAtOffset = (dataNo0x: string, offsetBytes: bigint): string => {
  const offset = Number(offsetBytes);
  const offsetHexIndex = offset * 2;

  const lengthWord = dataNo0x.slice(offsetHexIndex, offsetHexIndex + 64);
  const length = Number(BigInt(`0x${lengthWord}`));

  const payloadStart = offsetHexIndex + 64;
  const payloadEnd = payloadStart + length * 2;

  const payloadHex = dataNo0x.slice(payloadStart, payloadEnd);
  return Buffer.from(payloadHex, 'hex').toString('utf8');
};

export const decodeIndexedEvent = (log: RawRpcLog): DecodedRescueEvent | null => {
  if (!log.topics || log.topics.length === 0) {
    return null;
  }

  const topic0 = log.topics[0].toLowerCase();
  const dataNo0x = strip0x(log.data || '0x');

  if (topic0 === EVENT_TOPICS.PositionUpdated) {
    return {
      eventName: 'PositionUpdated',
      execId: null,
      userAddress: log.topics[1] ? topicToAddress(log.topics[1]) : null,
      messageId: null,
      payload: {
        collateral: readUintWord(dataNo0x, 0),
        debt: readUintWord(dataNo0x, 1),
        hfWad: readUintWord(dataNo0x, 2),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.RescueInitiated) {
    return {
      eventName: 'RescueInitiated',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: log.topics[2] ? topicToAddress(log.topics[2]) : null,
      messageId: null,
      payload: {
        steps: readUintWord(dataNo0x, 0),
        deadline: readUintWord(dataNo0x, 1),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.RescueStepCompleted) {
    return {
      eventName: 'RescueStepCompleted',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: null,
      messageId: null,
      payload: {
        stepIndex: log.topics[2] ? BigInt(log.topics[2]).toString() : '0',
        sourceAdapter: readAddressWord(dataNo0x, 0),
        targetAdapter: readAddressWord(dataNo0x, 1),
        collateralAmount: readUintWord(dataNo0x, 2),
        debtAmount: readUintWord(dataNo0x, 3),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.RescueCompleted) {
    return {
      eventName: 'RescueCompleted',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: log.topics[2] ? topicToAddress(log.topics[2]) : null,
      messageId: null,
      payload: {
        status: readUintWord(dataNo0x, 0),
        finalStepIndex: readUintWord(dataNo0x, 1),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.RescueFailed) {
    const reasonOffset = wordToBigInt(readWord(dataNo0x, 0));
    return {
      eventName: 'RescueFailed',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: log.topics[2] ? topicToAddress(log.topics[2]) : null,
      messageId: null,
      payload: {
        reason: decodeStringAtOffset(dataNo0x, reasonOffset),
        failedStepIndex: readUintWord(dataNo0x, 1),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.CrossChainInitiated) {
    return {
      eventName: 'CrossChainInitiated',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: null,
      messageId: log.topics[3]?.toLowerCase() ?? null,
      payload: {
        targetChain: log.topics[2] ? BigInt(log.topics[2]).toString() : '0',
        feePaid: readUintWord(dataNo0x, 0),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.CrossChainCompleted) {
    return {
      eventName: 'CrossChainCompleted',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: null,
      messageId: log.topics[2]?.toLowerCase() ?? null,
      payload: {
        amountReceived: readUintWord(dataNo0x, 0),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.CrossChainDestinationFailed) {
    const reasonOffset = wordToBigInt(readWord(dataNo0x, 0));
    return {
      eventName: 'CrossChainDestinationFailed',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: null,
      messageId: log.topics[2]?.toLowerCase() ?? null,
      payload: {
        reason: decodeStringAtOffset(dataNo0x, reasonOffset),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.EscrowCreated) {
    const relatedExecId = readBytes32Word(dataNo0x, 2);
    return {
      eventName: 'EscrowCreated',
      execId: relatedExecId,
      userAddress: log.topics[2] ? topicToAddress(log.topics[2]) : null,
      messageId: null,
      payload: {
        escrowId: log.topics[1]?.toLowerCase() ?? null,
        owner: log.topics[2] ? topicToAddress(log.topics[2]) : null,
        asset: readAddressWord(dataNo0x, 0),
        amount: readUintWord(dataNo0x, 1),
        relatedExecId,
      },
    };
  }

  if (topic0 === EVENT_TOPICS.LogEntryAdded) {
    const detailsOffset = wordToBigInt(readWord(dataNo0x, 1));
    return {
      eventName: 'LogEntryAdded',
      execId: log.topics[1]?.toLowerCase() ?? null,
      userAddress: log.topics[3] ? topicToAddress(log.topics[3]) : null,
      messageId: null,
      payload: {
        stepIndex: log.topics[2] ? BigInt(log.topics[2]).toString() : '0',
        status: readUintWord(dataNo0x, 0),
        details: decodeStringAtOffset(dataNo0x, detailsOffset),
      },
    };
  }

  if (topic0 === EVENT_TOPICS.MessageFailed) {
    const reasonOffset = wordToBigInt(readWord(dataNo0x, 0));
    return {
      eventName: 'MessageFailed',
      execId: log.topics[3]?.toLowerCase() ?? null,
      userAddress: null,
      messageId: log.topics[1]?.toLowerCase() ?? null,
      payload: {
        sourceChainSelector: log.topics[2] ? BigInt(log.topics[2]).toString() : '0',
        reason: decodeStringAtOffset(dataNo0x, reasonOffset),
      },
    };
  }

  return null;
};
