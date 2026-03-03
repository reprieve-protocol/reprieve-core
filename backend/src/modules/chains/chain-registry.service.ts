import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  SUPPORTED_CHAINS,
  SUPPORTED_CHAIN_KEYS,
  SupportedChainKey,
  SupportedChainMetadata,
} from '../../config/chains.config';

export interface RegisteredChain extends SupportedChainMetadata {
  rpcUrl: string;
  startBlock: number;
}

@Injectable()
export class ChainRegistryService {
  constructor(private readonly configService: ConfigService) {}

  getAll(): RegisteredChain[] {
    return SUPPORTED_CHAIN_KEYS.map((key) => this.getByKey(key));
  }

  getByKey(chainKey: SupportedChainKey): RegisteredChain {
    const baseConfig = SUPPORTED_CHAINS[chainKey];
    if (!baseConfig) {
      throw new NotFoundException(`Unsupported chain: ${chainKey}`);
    }

    const rpcUrl = this.configService.getOrThrow<string>(baseConfig.envRpcKey);
    const startBlock = Number(
      this.configService.get<string>(baseConfig.envStartBlockKey, '0'),
    );

    return {
      ...baseConfig,
      rpcUrl,
      startBlock,
    };
  }
}
