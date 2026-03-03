import { Injectable } from '@nestjs/common';
import {
  decodeDiscoverPositionsResult,
  encodeDiscoverPositionsCalldata,
} from './abi';
import { AdapterReadResult } from './types';

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
export class AdapterReaderService {
  async discoverPositions(
    rpcUrl: string,
    adapterAddress: string,
    userAddress: string,
  ): Promise<AdapterReadResult> {
    const calldata = encodeDiscoverPositionsCalldata(userAddress);

    const payload = {
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'eth_call',
      params: [
        {
          to: adapterAddress,
          data: calldata,
        },
        'latest',
      ],
    };

    const response = await fetch(rpcUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`RPC request failed with status ${response.status}`);
    }

    const data = (await response.json()) as JsonRpcResponse<string>;

    if (data.error) {
      throw new Error(`RPC eth_call failed: ${data.error.message}`);
    }

    if (typeof data.result !== 'string') {
      throw new Error('RPC eth_call returned invalid result');
    }

    return {
      positions: decodeDiscoverPositionsResult(data.result),
    };
  }
}
