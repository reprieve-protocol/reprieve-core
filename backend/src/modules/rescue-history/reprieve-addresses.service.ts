import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { SUPPORTED_CHAIN_KEYS, SupportedChainKey } from '../../config/chains.config';
import { ChainRegistryService } from '../chains/chain-registry.service';
import { EvmRpcService } from './evm-rpc.service';

interface ReprieveStackConfig {
  chainId: number;
  contracts?: Record<string, string>;
}

interface LendingContractsConfig {
  chainId: number;
  contracts?: Record<string, string>;
}

@Injectable()
export class ReprieveAddressesService {
  private readonly cache = new Map<number, { expiresAtMs: number; addresses: string[] }>();

  constructor(
    private readonly configService: ConfigService,
    private readonly chainRegistryService: ChainRegistryService,
    private readonly evmRpcService: EvmRpcService,
  ) {}

  async getIndexedContractAddresses(chainId: number): Promise<string[]> {
    const cached = this.cache.get(chainId);
    const now = Date.now();
    if (cached && cached.expiresAtMs > now) {
      return cached.addresses;
    }

    const reprieveContracts = this.loadReprieveStackConfig(chainId).contracts ?? {};
    const chainKey = this.resolveChainKeyFromChainId(chainId);
    const chainConfig = this.chainRegistryService.getByKey(chainKey);
    const lendingContracts = this.loadLendingContractsConfig(chainKey).contracts ?? {};

    const reprieveAddresses = [
      reprieveContracts.RescueExecutor,
      reprieveContracts.RescueLog,
      reprieveContracts.CCIPReceiver,
      reprieveContracts.RescueEscrow,
    ];

    const protocolAddresses = [
      lendingContracts.MockAavePool,
      lendingContracts.MockCompoundComet,
      lendingContracts.MockMorphoMarket,
      lendingContracts.AaveLikeAdapter,
      lendingContracts.CompoundLikeAdapter,
      lendingContracts.MorphoLikeAdapter,
    ];

    const marketAddresses = [
      lendingContracts.MockAavePool,
      lendingContracts.MockCompoundComet,
      lendingContracts.MockMorphoMarket,
    ]
      .filter((value): value is string => typeof value === 'string' && value.length > 0)
      .map((value) => value.toLowerCase());

    const engineAddresses = await Promise.all(
      marketAddresses.map((marketAddress) =>
        this.evmRpcService.readAddressResult(
          chainConfig.rpcUrl,
          marketAddress,
          // engine()
          '0xc9d4623f',
        ),
      ),
    );

    const addresses = [
      ...reprieveAddresses,
      ...protocolAddresses,
      ...engineAddresses,
    ]
      .filter((value): value is string => typeof value === 'string' && value.length > 0)
      .map((value) => value.toLowerCase());

    const unique = Array.from(new Set(addresses));
    this.cache.set(chainId, {
      addresses: unique,
      expiresAtMs: now + 30_000,
    });

    return unique;
  }

  private loadReprieveStackConfig(chainId: number): ReprieveStackConfig {
    const baseDir = this.configService.get<string>(
      'CONTRACTS_CONFIG_DIR',
      '../contracts/config',
    );

    const filePath = path.resolve(
      process.cwd(),
      baseDir,
      `reprieve-stack-${chainId}.json`,
    );

    if (!fs.existsSync(filePath)) {
      throw new Error(`Reprieve stack config missing for chain ${chainId}: ${filePath}`);
    }

    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as ReprieveStackConfig;
  }

  private loadLendingContractsConfig(chainKey: SupportedChainKey): LendingContractsConfig {
    const baseDir = this.configService.get<string>(
      'CONTRACTS_CONFIG_DIR',
      '../contracts/config',
    );

    const filePath = path.resolve(process.cwd(), baseDir, `${chainKey}.json`);
    if (!fs.existsSync(filePath)) {
      throw new Error(`Lending contracts config missing for ${chainKey}: ${filePath}`);
    }

    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as LendingContractsConfig;
  }

  private resolveChainKeyFromChainId(chainId: number): SupportedChainKey {
    const match = SUPPORTED_CHAIN_KEYS.find((key) => {
      const chain = this.chainRegistryService.getByKey(key);
      return chain.chainId === chainId;
    });

    if (!match) {
      throw new Error(`Unsupported chain id for address indexing: ${chainId}`);
    }

    return match;
  }
}
