import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { Repository } from 'typeorm';
import { SUPPORTED_CHAIN_KEYS, SupportedChainKey } from '../../config/chains.config';
import { ChainRegistryService } from '../chains/chain-registry.service';
import {
  ChainEntity,
  PositionSnapshotEntity,
  ProtocolAdapterEntity,
} from '../persistence/entities';
import { AdapterReaderService } from './adapter-reader.service';
import { PositionSyncError } from './types';

interface ChainContractsConfig {
  contracts?: Record<string, string>;
}

@Injectable()
export class PositionsService {
  constructor(
    private readonly chainRegistryService: ChainRegistryService,
    private readonly adapterReaderService: AdapterReaderService,
    private readonly configService: ConfigService,
    @InjectRepository(ChainEntity)
    private readonly chainRepository: Repository<ChainEntity>,
    @InjectRepository(ProtocolAdapterEntity)
    private readonly protocolAdapterRepository: Repository<ProtocolAdapterEntity>,
    @InjectRepository(PositionSnapshotEntity)
    private readonly positionSnapshotRepository: Repository<PositionSnapshotEntity>,
  ) {}

  async syncPositions(userAddress: string): Promise<{
    status: string;
    errors: PositionSyncError[];
    snapshotsUpserted: number;
  }> {
    const errors: PositionSyncError[] = [];
    let snapshotsUpserted = 0;

    await this.ensureChainsSeeded();
    await this.ensureProtocolAdaptersSeeded();

    const enabledChains = await this.chainRepository.find({
      where: { isEnabled: true },
      order: { chainId: 'ASC' },
    });

    for (const chain of enabledChains) {
      const chainKey = this.resolveChainKeyFromChainId(chain.chainId);
      const chainConfig = this.chainRegistryService.getByKey(chainKey);

      const adapters = await this.protocolAdapterRepository.find({
        where: {
          chainId: chain.chainId,
          isEnabled: true,
        },
      });

      for (const adapter of adapters) {
        try {
          const discovered = await this.adapterReaderService.discoverPositions(
            chainConfig.rpcUrl,
            adapter.adapterAddress,
            userAddress,
          );

          if (discovered.positions.length === 0) {
            continue;
          }

          for (const discoveredPosition of discovered.positions) {
            await this.positionSnapshotRepository.upsert(
              {
                userAddress: userAddress.toLowerCase(),
                chainId: chain.chainId,
                protocol: adapter.protocol,
                adapterAddress: adapter.adapterAddress,
                collateralAsset: discoveredPosition.collateralAsset.toLowerCase(),
                debtAsset: discoveredPosition.debtAsset.toLowerCase(),
                collateralAmountRaw: discoveredPosition.collateralAmount,
                debtAmountRaw: discoveredPosition.debtAmount,
                healthFactorWad: discoveredPosition.healthFactor,
                ltvBps: Number(discoveredPosition.ltvBps),
                maxLtvBps: Number(discoveredPosition.maxLtvBps),
                liquidationThresholdBps: Number(
                  discoveredPosition.liquidationThresholdBps,
                ),
                syncedAt: new Date(),
                updatedAt: new Date(),
              },
              {
                conflictPaths: [
                  'userAddress',
                  'chainId',
                  'adapterAddress',
                  'collateralAsset',
                  'debtAsset',
                ],
                skipUpdateIfNoValuesChanged: false,
              },
            );

            snapshotsUpserted += 1;
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : 'unknown error';
          errors.push({
            chainId: chain.chainId,
            chainKey,
            protocol: adapter.protocol,
            adapterAddress: adapter.adapterAddress,
            reason: message,
          });
        }
      }
    }

    return {
      status: errors.length > 0 ? 'failed' : 'success',
      errors,
      snapshotsUpserted,
    };
  }

  async getPositions(userAddress: string): Promise<{
    user: string;
    syncedAt: string | null;
    positions: PositionSnapshotEntity[];
  }> {
    const positions = await this.positionSnapshotRepository.find({
      where: {
        userAddress: userAddress.toLowerCase(),
      },
      order: {
        syncedAt: 'DESC',
      },
    });

    const newestSyncedAt = positions.length > 0 ? positions[0].syncedAt : null;

    return {
      user: userAddress.toLowerCase(),
      syncedAt: newestSyncedAt ? newestSyncedAt.toISOString() : null,
      positions,
    };
  }

  private async ensureChainsSeeded(): Promise<void> {
    const existing = await this.chainRepository.count();
    if (existing > 0) {
      return;
    }

    for (const key of SUPPORTED_CHAIN_KEYS) {
      const chainConfig = this.chainRegistryService.getByKey(key);

      await this.chainRepository.save({
        key,
        chainId: chainConfig.chainId,
        rpcUrl: chainConfig.rpcUrl,
        isEnabled: true,
      });
    }
  }

  private async ensureProtocolAdaptersSeeded(): Promise<void> {
    const existing = await this.protocolAdapterRepository.count();
    if (existing > 0) {
      return;
    }

    const chains = await this.chainRepository.find({ where: { isEnabled: true } });

    for (const chain of chains) {
      const chainKey = this.resolveChainKeyFromChainId(chain.chainId);
      const config = this.loadChainContractsConfig(chainKey);
      const contracts = config.contracts ?? {};

      const collateralAsset = contracts.MockERC20_Collateral;
      const debtAsset = contracts.MockERC20_Debt;

      const adapterRows: Array<Partial<ProtocolAdapterEntity>> = [];

      if (contracts.AaveLikeAdapter && contracts.MockAavePool) {
        adapterRows.push({
          chainId: chain.chainId,
          protocol: 'AAVE',
          adapterAddress: contracts.AaveLikeAdapter.toLowerCase(),
          marketAddress: contracts.MockAavePool.toLowerCase(),
          collateralAsset: collateralAsset?.toLowerCase(),
          debtAsset: debtAsset?.toLowerCase(),
          isEnabled: true,
        });
      }

      if (contracts.CompoundLikeAdapter && contracts.MockCompoundComet) {
        adapterRows.push({
          chainId: chain.chainId,
          protocol: 'COMPOUND',
          adapterAddress: contracts.CompoundLikeAdapter.toLowerCase(),
          marketAddress: contracts.MockCompoundComet.toLowerCase(),
          collateralAsset: collateralAsset?.toLowerCase(),
          debtAsset: debtAsset?.toLowerCase(),
          isEnabled: true,
        });
      }

      if (contracts.MorphoLikeAdapter && contracts.MockMorphoMarket) {
        adapterRows.push({
          chainId: chain.chainId,
          protocol: 'MORPHO',
          adapterAddress: contracts.MorphoLikeAdapter.toLowerCase(),
          marketAddress: contracts.MockMorphoMarket.toLowerCase(),
          collateralAsset: collateralAsset?.toLowerCase(),
          debtAsset: debtAsset?.toLowerCase(),
          isEnabled: true,
        });
      }

      for (const row of adapterRows) {
        if (!row.collateralAsset || !row.debtAsset) {
          continue;
        }
        await this.protocolAdapterRepository.upsert(row, {
          conflictPaths: ['chainId', 'adapterAddress'],
          skipUpdateIfNoValuesChanged: false,
        });
      }
    }
  }

  private loadChainContractsConfig(chainKey: SupportedChainKey): ChainContractsConfig {
    const baseDir = this.configService.get<string>(
      'CONTRACTS_CONFIG_DIR',
      '../contracts/config',
    );

    const filePath = path.resolve(process.cwd(), baseDir, `${chainKey}.json`);
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as ChainContractsConfig;
  }

  private resolveChainKeyFromChainId(chainId: number): SupportedChainKey {
    const match = SUPPORTED_CHAIN_KEYS.find((key) => {
      const chain = this.chainRegistryService.getByKey(key);
      return chain.chainId === chainId;
    });

    if (!match) {
      throw new Error(`Unsupported chain id: ${chainId}`);
    }

    return match;
  }
}
