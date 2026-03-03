export interface RawRpcLog {
  address: string;
  blockNumber: string;
  transactionHash: string;
  logIndex: string;
  data: string;
  topics: string[];
}

export interface DecodedRescueEvent {
  eventName: string;
  execId: string | null;
  userAddress: string | null;
  messageId: string | null;
  payload: Record<string, unknown>;
}

export interface ChainIndexProgress {
  chainId: number;
  chainKey: string;
  fromBlock: string | null;
  toBlock: string | null;
  scannedLogs: number;
  decodedLogs: number;
  status: 'idle' | 'indexed' | 'error';
  error?: string;
}

export interface IndexerRunResult {
  startedAt: string;
  finishedAt: string;
  totalChains: number;
  totalLogsScanned: number;
  totalLogsDecoded: number;
  chains: ChainIndexProgress[];
}
