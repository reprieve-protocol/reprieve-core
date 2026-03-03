import { Injectable } from '@nestjs/common';
import { INDEXED_EVENT_TOPIC_LIST } from './event-topics';
import { RawRpcLog } from './types';

interface JsonRpcResponse<T> {
  jsonrpc: string;
  id: number;
  result?: T;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
}

@Injectable()
export class EvmRpcService {
  private async rpcCall<T>(
    rpcUrl: string,
    method: string,
    params: unknown[],
  ): Promise<T> {
    const payload = {
      jsonrpc: '2.0',
      id: Date.now(),
      method,
      params,
    };

    const response = await fetch(rpcUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`RPC request failed (${method}) with status ${response.status}`);
    }

    const data = (await response.json()) as JsonRpcResponse<T>;

    if (data.error) {
      throw new Error(`RPC ${method} failed: ${data.error.message}`);
    }

    if (data.result === undefined) {
      throw new Error(`RPC ${method} returned empty result`);
    }

    return data.result;
  }

  async getLatestBlockNumber(rpcUrl: string): Promise<bigint> {
    const result = await this.rpcCall<string>(rpcUrl, 'eth_blockNumber', []);
    return BigInt(result);
  }

  async getIndexedLogs(
    rpcUrl: string,
    addresses: string[],
    fromBlock: bigint,
    toBlock: bigint,
  ): Promise<RawRpcLog[]> {
    if (addresses.length === 0) {
      return [];
    }

    const filter = {
      address: addresses,
      fromBlock: `0x${fromBlock.toString(16)}`,
      toBlock: `0x${toBlock.toString(16)}`,
      topics: [INDEXED_EVENT_TOPIC_LIST],
    };

    return this.rpcCall<RawRpcLog[]>(rpcUrl, 'eth_getLogs', [filter]);
  }

  async ethCall(rpcUrl: string, to: string, data: string): Promise<string> {
    return this.rpcCall<string>(rpcUrl, 'eth_call', [{ to, data }, 'latest']);
  }

  async readAddressResult(
    rpcUrl: string,
    to: string,
    data: string,
  ): Promise<string | null> {
    try {
      const result = await this.ethCall(rpcUrl, to, data);
      const normalized = result.startsWith('0x') ? result.slice(2) : result;
      if (normalized.length < 64) {
        return null;
      }
      return `0x${normalized.slice(24, 64)}`.toLowerCase();
    } catch {
      return null;
    }
  }
}
