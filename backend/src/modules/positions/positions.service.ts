import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import * as fs from 'node:fs';
import { Interface, ZeroAddress } from 'ethers';
import { In, Not, Repository } from 'typeorm';
import { SUPPORTED_CHAIN_KEYS, SupportedChainKey } from '../../config/chains.config';
import { ChainRegistryService } from '../chains/chain-registry.service';
import { resolveContractsConfigFilePath } from '../chains/contracts-config-path.util';
import {
  ChainEntity,
  PositionSnapshotEntity,
  ProtocolAdapterEntity,
} from '../persistence/entities';
import { AdapterReaderService } from './adapter-reader.service';
import { SimulateApiGuardDto } from './positions.dto';
import { PositionSyncError } from './types';

interface ChainContractsConfig {
  chainId?: number;
  contracts?: Record<string, string>;
  tokenParams?: {
    collateral?: { decimals?: number };
    debt?: { decimals?: number };
  };
}

interface ChainTokenMeta {
  collateralAsset: string;
  debtAsset: string;
  collateralDecimals: number;
  debtDecimals: number;
  oracleAddress: string;
}

const ERC20_METADATA_ABI = ['function decimals() view returns (uint8)'] as const;
const ORACLE_ABI = [
  'function getPrice(address asset) view returns (uint256 price, uint256 updatedAt)',
] as const;
const ERC20_SYMBOL_STRING_ABI = ['function symbol() view returns (string)'] as const;
const ERC20_SYMBOL_BYTES32_ABI = ['function symbol() view returns (bytes32)'] as const;
const WAD = 10n ** 18n;
const BPS_DENOM = 10_000n;
const MAX_UINT256 = (1n << 256n) - 1n;
const ETHEREUM_SEPOLIA_CHAIN_ID = 11155111;

type Decision = 'NO_ACTION' | 'RESCUE_SAME_CHAIN' | 'RESCUE_CROSS_CHAIN' | 'ABORT';
type RescueMode = 'TOP_UP' | 'REPAY';

interface SimPosition {
  chainId: number;
  chainKey: string;
  protocol: string;
  adapterAddress: string;
  collateralAsset: string;
  debtAsset: string;
  collateralAmountRaw: bigint;
  debtAmountRaw: bigint;
  healthFactorWad: bigint;
  liquidationThresholdBps: bigint;
  collateralDecimals: number;
  debtDecimals: number;
  collateralPriceWad: bigint | null;
  debtPriceWad: bigint | null;
}

interface FlatPosition {
  label: string;
  adapterAddress: string;
  availableCollateral: bigint;
  chainId: number;
  chainKey: string;
  position: SimPosition;
}

@Injectable()
export class PositionsService {
  private readonly logger = new Logger(PositionsService.name);
  private readonly erc20MetadataInterface = new Interface(ERC20_METADATA_ABI);
  private readonly oracleInterface = new Interface(ORACLE_ABI);
  private readonly erc20SymbolStringInterface = new Interface(ERC20_SYMBOL_STRING_ABI);
  private readonly erc20SymbolBytes32Interface = new Interface(ERC20_SYMBOL_BYTES32_ABI);

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

  async getOraclePrice(
    chainKey: SupportedChainKey,
    assetAddress: string,
  ): Promise<{
    chainKey: SupportedChainKey;
    chainId: number;
    oracleAddress: string;
    asset: string;
    priceWad: string;
    priceUsd: string;
    updatedAt: string;
    updatedAtIso: string | null;
  }> {
    const chain = this.chainRegistryService.getByKey(chainKey);
    const contractsConfig = this.loadChainContractsConfig(chainKey);
    const oracleAddress = (
      contractsConfig.contracts?.MockPriceOracle ?? ZeroAddress
    ).toLowerCase();
    if (oracleAddress === ZeroAddress.toLowerCase()) {
      throw new BadRequestException(
        `MockPriceOracle is not configured for chain ${chainKey}`,
      );
    }

    const normalizedAsset = assetAddress.toLowerCase();
    const calldata = this.oracleInterface.encodeFunctionData('getPrice', [
      normalizedAsset,
    ]);
    const rawResult = await this.ethCall(chain.rpcUrl, oracleAddress, calldata);
    const decoded = this.oracleInterface.decodeFunctionResult('getPrice', rawResult);
    const priceWad = decoded[0] as bigint;
    const updatedAt = decoded[1] as bigint;

    let updatedAtIso: string | null = null;
    if (updatedAt > 0n) {
      const updatedAtMillis = Number(updatedAt) * 1000;
      if (!Number.isSafeInteger(updatedAtMillis)) {
        throw new BadRequestException(
          `Oracle timestamp is too large to format safely for ${chainKey}:${normalizedAsset}`,
        );
      }
      updatedAtIso = new Date(updatedAtMillis).toISOString();
    }

    return {
      chainKey,
      chainId: chain.chainId,
      oracleAddress,
      asset: normalizedAsset,
      priceWad: priceWad.toString(),
      priceUsd: this.wadToFixed(priceWad, 8),
      updatedAt: updatedAt.toString(),
      updatedAtIso,
    };
  }

  async getRiskSnapshot(
    userAddress: string,
    maxAgeSec = 600,
  ): Promise<{
    user: string;
    generatedAt: string;
    latestSyncedAt: string | null;
    oldestSyncedAt: string | null;
    latestAgeSec: number;
    maxAgeSec: number;
    isStale: boolean;
    positionCount: number;
    chains: Array<{
      chainId: number;
      chainKey: string;
      indexerCursorBlock: string | null;
    }>;
      positions: Array<{
      chainId: number;
      chainKey: string;
      protocol: string;
      adapterAddress: string;
      collateralAsset: string;
      debtAsset: string;
      collateralAmountRaw: string;
      debtAmountRaw: string;
      healthFactorWad: string;
      ltvBps: number | null;
      maxLtvBps: number | null;
      liquidationThresholdBps: number | null;
      collateralDecimals: number;
      debtDecimals: number;
      syncedAt: string;
      collateralPriceWad: string | null;
      debtPriceWad: string | null;
    }>;
  }> {
    const normalizedUser = userAddress.toLowerCase();
    const positions = await this.positionSnapshotRepository.find({
      where: { userAddress: normalizedUser },
      order: { syncedAt: 'DESC' },
    });

    const chainIds = Array.from(new Set(positions.map((p) => p.chainId)));
    const chains =
      chainIds.length === 0
        ? []
        : await this.chainRepository.find({
            where: {
              chainId: In(chainIds),
            },
            order: { chainId: 'ASC' },
          });

    const chainById = new Map<number, ChainEntity>();
    for (const chain of chains) {
      chainById.set(chain.chainId, chain);
    }

    const tokenMetaByChain = new Map<number, ChainTokenMeta>();
    for (const chain of chains) {
      const chainKey = chain.key as SupportedChainKey;
      if (!SUPPORTED_CHAIN_KEYS.includes(chainKey)) {
        continue;
      }
      const config = this.loadChainContractsConfig(chainKey);
      const contracts = config.contracts ?? {};
      tokenMetaByChain.set(chain.chainId, {
        collateralAsset: (contracts.MockERC20_Collateral ?? '').toLowerCase(),
        debtAsset: (contracts.MockERC20_Debt ?? '').toLowerCase(),
        collateralDecimals: config.tokenParams?.collateral?.decimals ?? 18,
        debtDecimals: config.tokenParams?.debt?.decimals ?? 18,
        oracleAddress: (contracts.MockPriceOracle ?? ZeroAddress).toLowerCase(),
      });
    }

    const decimalsCache = new Map<string, number>();
    const priceCache = new Map<string, bigint>();

    const now = Date.now();
    const latestSyncedAt = positions.length > 0 ? positions[0].syncedAt : null;
    const oldestSyncedAt =
      positions.length > 0 ? positions[positions.length - 1].syncedAt : null;
    const latestAgeSec = latestSyncedAt
      ? Math.floor((now - latestSyncedAt.getTime()) / 1000)
      : Number.MAX_SAFE_INTEGER;
    const stale = latestAgeSec > maxAgeSec;

    const enrichedPositions = await Promise.all(
      positions.map(async (position) => {
        const chain = chainById.get(position.chainId);
        const meta = tokenMetaByChain.get(position.chainId);
        const collateralAsset = position.collateralAsset.toLowerCase();
        const debtAsset = position.debtAsset.toLowerCase();

        let collateralDecimals =
          meta && collateralAsset === meta.collateralAsset
            ? meta.collateralDecimals
            : 18;
        let debtDecimals =
          meta && debtAsset === meta.debtAsset ? meta.debtDecimals : 18;

        let collateralPriceWad: bigint | null = null;
        let debtPriceWad: bigint | null = null;
        let healthFactorWad = position.healthFactorWad;

        if (chain && meta && meta.oracleAddress !== ZeroAddress.toLowerCase()) {
          try {
            const chainConfig = this.chainRegistryService.getByKey(
              this.resolveChainKeyFromChainId(position.chainId),
            );
            collateralDecimals = await this.readTokenDecimals(
              chainConfig.rpcUrl,
              collateralAsset,
              decimalsCache,
              `${position.chainId}:collateral:${collateralAsset}`,
              collateralDecimals,
            );
            debtDecimals = await this.readTokenDecimals(
              chainConfig.rpcUrl,
              debtAsset,
              decimalsCache,
              `${position.chainId}:debt:${debtAsset}`,
              debtDecimals,
            );
            collateralPriceWad = await this.readOraclePriceWad(
              chainConfig.rpcUrl,
              meta.oracleAddress,
              collateralAsset,
              priceCache,
              `${position.chainId}:oracle:${meta.oracleAddress}:${collateralAsset}`,
            );
            debtPriceWad = await this.readOraclePriceWad(
              chainConfig.rpcUrl,
              meta.oracleAddress,
              debtAsset,
              priceCache,
              `${position.chainId}:oracle:${meta.oracleAddress}:${debtAsset}`,
            );

            // Match CRE risk-v1 fallback semantics: missing LT defaults to 8000 bps.
            const liquidationThresholdBps = position.liquidationThresholdBps ?? 8000;
            healthFactorWad = this.computeHealthFactorWad({
              collateralAmountRaw: BigInt(position.collateralAmountRaw),
              debtAmountRaw: BigInt(position.debtAmountRaw),
              collateralPriceWad,
              debtPriceWad,
              collateralDecimals,
              debtDecimals,
              liquidationThresholdBps,
            }).toString();
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            this.logger.warn(
              `Risk snapshot HF recalculation fallback for chainId=${position.chainId} adapter=${position.adapterAddress}: ${message}`,
            );
          }
        }

        return {
          chainId: position.chainId,
          chainKey: chain?.key ?? 'unknown',
          protocol: position.protocol,
          adapterAddress: position.adapterAddress,
          collateralAsset,
          debtAsset,
          collateralAmountRaw: position.collateralAmountRaw,
          debtAmountRaw: position.debtAmountRaw,
          healthFactorWad,
          ltvBps: position.ltvBps,
          maxLtvBps: position.maxLtvBps,
          liquidationThresholdBps: position.liquidationThresholdBps,
          collateralDecimals,
          debtDecimals,
          syncedAt: position.syncedAt.toISOString(),
          collateralPriceWad: collateralPriceWad?.toString() ?? null,
          debtPriceWad: debtPriceWad?.toString() ?? null,
        };
      }),
    );

    // Align backend risk snapshot pricing with CRE canonical-asset semantics:
    // base assets are valued using mapped ethereum canonical asset prices when available.
    const canonicalAssetMap = this.buildCanonicalAssetMapFromChainConfigs();
    const canonicalPriceByAsset = new Map<
      string,
      { priceWad: bigint; sourceChainId: number }
    >();

    const registerCanonicalPrice = (
      asset: string,
      priceWad: string | null,
      sourceChainId: number,
    ): void => {
      if (!priceWad) return;
      const parsed = BigInt(priceWad);
      if (parsed <= 0n) return;
      const canonicalAsset =
        canonicalAssetMap.get(asset.toLowerCase()) ?? asset.toLowerCase();
      const existing = canonicalPriceByAsset.get(canonicalAsset);
      if (!existing) {
        canonicalPriceByAsset.set(canonicalAsset, {
          priceWad: parsed,
          sourceChainId,
        });
        return;
      }
      if (
        sourceChainId === ETHEREUM_SEPOLIA_CHAIN_ID &&
        existing.sourceChainId !== ETHEREUM_SEPOLIA_CHAIN_ID
      ) {
        canonicalPriceByAsset.set(canonicalAsset, {
          priceWad: parsed,
          sourceChainId,
        });
      }
    };

    for (const position of enrichedPositions) {
      registerCanonicalPrice(
        position.collateralAsset,
        position.collateralPriceWad,
        position.chainId,
      );
      registerCanonicalPrice(position.debtAsset, position.debtPriceWad, position.chainId);
    }

    const normalizedPositions = enrichedPositions.map((position) => {
      const canonicalCollateral =
        canonicalAssetMap.get(position.collateralAsset) ?? position.collateralAsset;
      const canonicalDebt =
        canonicalAssetMap.get(position.debtAsset) ?? position.debtAsset;

      const mappedCollateralPriceWad =
        canonicalPriceByAsset.get(canonicalCollateral)?.priceWad ??
        (position.collateralPriceWad ? BigInt(position.collateralPriceWad) : null);
      const mappedDebtPriceWad =
        canonicalPriceByAsset.get(canonicalDebt)?.priceWad ??
        (position.debtPriceWad ? BigInt(position.debtPriceWad) : null);

      let healthFactorWad = position.healthFactorWad;
      if (mappedCollateralPriceWad && mappedDebtPriceWad) {
        healthFactorWad = this.computeHealthFactorWad({
          collateralAmountRaw: BigInt(position.collateralAmountRaw),
          debtAmountRaw: BigInt(position.debtAmountRaw),
          collateralPriceWad: mappedCollateralPriceWad,
          debtPriceWad: mappedDebtPriceWad,
          collateralDecimals: position.collateralDecimals,
          debtDecimals: position.debtDecimals,
          liquidationThresholdBps: position.liquidationThresholdBps ?? 8000,
        }).toString();
      }

      return {
        ...position,
        healthFactorWad,
        collateralPriceWad: mappedCollateralPriceWad?.toString() ?? null,
        debtPriceWad: mappedDebtPriceWad?.toString() ?? null,
      };
    });

    return {
      user: normalizedUser,
      generatedAt: new Date(now).toISOString(),
      latestSyncedAt: latestSyncedAt ? latestSyncedAt.toISOString() : null,
      oldestSyncedAt: oldestSyncedAt ? oldestSyncedAt.toISOString() : null,
      latestAgeSec,
      maxAgeSec,
      isStale: stale,
      positionCount: positions.length,
      chains: chains.map((chain) => ({
        chainId: chain.chainId,
        chainKey: chain.key,
        indexerCursorBlock: chain.indexerCursorBlock,
      })),
      positions: normalizedPositions,
    };
  }

  async simulateApiGuardDecision(
    userAddress: string,
    dto: SimulateApiGuardDto,
  ): Promise<Record<string, unknown>> {
    const maxAgeSec = dto.maxAgeSec ?? 600;
    const executionChainKey = (dto.executionChainKey ?? 'ethereum-sepolia').toLowerCase();
    const earlyWarningHfBps = dto.earlyWarningHfBps ?? 11250;
    const onchainHfMinBps = dto.onchainHfMinBps ?? 10000;
    const sourceFloorHfBps = dto.sourceFloorHfBps ?? 11250;
    const targetHfBps = dto.targetHfBps ?? 14500;
    const reserveCapBps = dto.reserveCapBps ?? 3000;
    const maxRescueNotionalUsd = dto.maxRescueNotionalUsd ?? 100000;
    const minActionUsd = dto.minActionUsd ?? 10;
    const allowCrossChain = dto.allowCrossChain ?? true;
    const forceCrossChain = dto.forceCrossChain ?? false;
    const sourceAdapterOverride = dto.sourceAdapter?.toLowerCase();
    const targetAdapterOverride = dto.targetAdapter?.toLowerCase();

    const snapshot = await this.getRiskSnapshot(userAddress, maxAgeSec);
    const simPositions = snapshot.positions.map((position) =>
      this.toSimPosition(position),
    );

    if (simPositions.length === 0) {
      return {
        decision: 'ABORT',
        reason: 'No positions found for monitored adapters',
        summary: {
          user: userAddress.toLowerCase(),
          positionCount: 0,
          isStale: snapshot.isStale,
          latestAgeSec: snapshot.latestAgeSec,
        },
      };
    }

    const flatPositions = this.flattenPositions(simPositions);
    const debtBearing = flatPositions
      .filter((item) => item.position.debtAmountRaw > 0n)
      .sort((a, b) => {
        if (a.position.healthFactorWad === b.position.healthFactorWad) return 0;
        return a.position.healthFactorWad < b.position.healthFactorWad ? -1 : 1;
      });

    if (debtBearing.length === 0) {
      return {
        decision: 'ABORT',
        reason: 'No debt-bearing positions found for rescue planning',
        summary: {
          user: userAddress.toLowerCase(),
          positionCount: simPositions.length,
          isStale: snapshot.isStale,
          latestAgeSec: snapshot.latestAgeSec,
        },
      };
    }

    const weakest = debtBearing[0];
    const weakestHfWad = weakest.position.healthFactorWad;
    const canCrossChain = flatPositions.some(
      (item) =>
        item.availableCollateral > 0n && item.chainId !== weakest.chainId,
    );
    const preDecision = this.decideRoute(
      weakestHfWad,
      this.bpsToWad(onchainHfMinBps),
      this.bpsToWad(earlyWarningHfBps),
      allowCrossChain,
      canCrossChain,
    );

    if (preDecision === 'NO_ACTION') {
      return {
        decision: 'NO_ACTION',
        reason: `Guard evaluated with weakest HF ${this.formatHf(weakestHfWad)}`,
        summary: {
          user: userAddress.toLowerCase(),
          positionCount: simPositions.length,
          isStale: snapshot.isStale,
          latestAgeSec: snapshot.latestAgeSec,
          weakestHfWad: weakestHfWad.toString(),
          weakestHf: this.formatHf(weakestHfWad),
          weakestAdapter: weakest.label,
        },
      };
    }

    const canonicalMap = await this.buildCanonicalAssetMap(simPositions);
    const target = targetAdapterOverride
      ? debtBearing.find((item) => item.adapterAddress === targetAdapterOverride)
      : weakest;

    if (!target) {
      return {
        decision: 'ABORT',
        reason: 'Requested target adapter is not debt-bearing for this user',
        summary: {
          user: userAddress.toLowerCase(),
          requestedTargetAdapter: targetAdapterOverride,
          weakestAdapter: weakest.label,
          weakestHf: this.formatHf(weakestHfWad),
        },
      };
    }

    const sourcePool = flatPositions.filter(
      (item) =>
        item.adapterAddress !== target.adapterAddress &&
        item.availableCollateral > 0n &&
        item.chainKey.toLowerCase() === executionChainKey,
    );

    const sourceCandidates = sourcePool
      .map((source) => ({
        source,
        mode: this.inferRescueModeFromPositions(source, target, canonicalMap),
      }))
      .filter(
        (
          item,
        ): item is { source: FlatPosition; mode: RescueMode } =>
          item.mode !== undefined,
      );

    if (sourceCandidates.length === 0) {
      return {
        decision: 'ABORT',
        reason:
          'No compatible rescue source with withdrawable collateral on execution chain',
        summary: {
          user: userAddress.toLowerCase(),
          executionChainKey,
          weakestHf: this.formatHf(weakestHfWad),
          weakestAdapter: target.label,
        },
      };
    }

    let selected: { source: FlatPosition; mode: RescueMode } | undefined;
    for (const candidate of sourceCandidates) {
      if (
        sourceAdapterOverride &&
        candidate.source.adapterAddress !== sourceAdapterOverride
      ) {
        continue;
      }
      if (
        !selected ||
        candidate.source.availableCollateral > selected.source.availableCollateral
      ) {
        selected = candidate;
      }
    }

    if (!selected) {
      return {
        decision: 'ABORT',
        reason: 'No eligible source after same-chain-first selection',
        summary: {
          user: userAddress.toLowerCase(),
          executionChainKey,
        },
      };
    }

    const source = selected.source;
    const mode = selected.mode;
    let isCrossChain = source.chainId !== target.chainId;
    if (forceCrossChain) {
      isCrossChain = true;
    }
    if (isCrossChain && !allowCrossChain) {
      return {
        decision: 'ABORT',
        reason:
          'Cross-chain rescue required by source/target location but disabled by policy',
        summary: {
          user: userAddress.toLowerCase(),
          sourceChain: source.chainKey,
          targetChain: target.chainKey,
        },
      };
    }

    const decimalsMap = this.buildDecimalsMap(simPositions);
    const pricesMap = this.buildPriceMap(simPositions);
    const getDecimals = (asset: string): number => decimalsMap.get(asset.toLowerCase()) ?? 18;
    const getPriceWad = (asset: string): bigint | undefined =>
      pricesMap.get(asset.toLowerCase());

    const desiredAmount = this.estimateNeededAction(
      mode,
      target,
      targetHfBps,
      getPriceWad,
      getDecimals,
    );

    const reserveSafeSource =
      (source.availableCollateral * BigInt(10000 - reserveCapBps)) / BPS_DENOM;
    const sourceHfSafeCap = this.computeSourceHfSafeCap(
      source,
      sourceFloorHfBps,
      getPriceWad,
      getDecimals,
    );

    let actionAmount = this.minBigInt(
      desiredAmount,
      this.minBigInt(reserveSafeSource, sourceHfSafeCap),
    );

    const sourceAsset = source.position.collateralAsset.toLowerCase();
    const sourcePrice = getPriceWad(sourceAsset);
    const sourceDecimals = getDecimals(sourceAsset);
    let actionUsdWad = 0n;

    if (sourcePrice && sourcePrice > 0n) {
      actionUsdWad = this.toUsdWad(actionAmount, sourceDecimals, sourcePrice);
      const maxNotionalUsdWad = BigInt(maxRescueNotionalUsd) * WAD;
      if (actionUsdWad > maxNotionalUsdWad) {
        actionAmount = this.fromUsdWadToAmount(
          maxNotionalUsdWad,
          sourceDecimals,
          sourcePrice,
        );
        actionUsdWad = this.toUsdWad(actionAmount, sourceDecimals, sourcePrice);
      }
    }

    if (actionAmount <= 0n) {
      return {
        decision: 'ABORT',
        reason: 'Computed rescue amount is zero after constraints',
        summary: {
          user: userAddress.toLowerCase(),
          mode,
          targetHfBps,
          desiredAmount: desiredAmount.toString(),
          reserveSafeSource: reserveSafeSource.toString(),
          sourceHfSafeCap: sourceHfSafeCap.toString(),
          sourceFloorHfBps,
        },
      };
    }

    if (sourcePrice && actionUsdWad < BigInt(minActionUsd) * WAD) {
      return {
        decision: 'NO_ACTION',
        reason: 'Computed rescue amount below minimum action threshold',
        summary: {
          user: userAddress.toLowerCase(),
          mode,
          targetHfBps,
          actionAmount: actionAmount.toString(),
          actionUsd: this.wadToFixed(actionUsdWad, 6),
          minActionUsd,
        },
      };
    }

    const destinationChainSelector = isCrossChain
      ? this.resolveChainSelectorByChainId(target.chainId)
      : '0';
    const decision: Decision = isCrossChain
      ? 'RESCUE_CROSS_CHAIN'
      : 'RESCUE_SAME_CHAIN';

    return {
      decision,
      reason: 'Rescue plan simulated from latest risk snapshot',
      summary: {
        user: userAddress.toLowerCase(),
        positionCount: simPositions.length,
        isStale: snapshot.isStale,
        latestAgeSec: snapshot.latestAgeSec,
        weakestHfWad: weakestHfWad.toString(),
        weakestHf: this.formatHf(weakestHfWad),
      },
      plan: {
        mode,
        src: `${source.position.protocol.toUpperCase()} - ${this.prettyChainLabel(source.chainKey)}`,
        targetAdapter: `${target.position.protocol.toUpperCase()} - ${this.prettyChainLabel(target.chainKey)}`,
        sourceAdapter: source.adapterAddress,
        collateralAsset: source.position.collateralAsset,
        debtAsset: target.position.debtAsset,
        collateralAmount: actionAmount.toString(),
        debtAmount: mode === 'REPAY' ? actionAmount.toString() : '0',
        isCrossChain,
        targetChain: destinationChainSelector,
      },
      debug: {
        targetHfBps,
        desiredAmount: desiredAmount.toString(),
        reserveSafeSource: reserveSafeSource.toString(),
        sourceHfSafeCap: sourceHfSafeCap.toString(),
        actionUsd: actionUsdWad.toString(),
        executionChainKey,
      },
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
    const chains = await this.chainRepository.find({ where: { isEnabled: true } });

    for (const chain of chains) {
      const chainKey = this.resolveChainKeyFromChainId(chain.chainId);
      const config = this.loadChainContractsConfig(chainKey);
      const contracts = config.contracts ?? {};

      const collateralAsset = contracts.MockERC20_Collateral;
      const debtAsset = contracts.MockERC20_Debt;

      const adapterRows: Array<Partial<ProtocolAdapterEntity>> = [];
      const activeProtocols: string[] = [];

      if (contracts.AaveLikeAdapter && contracts.MockAavePool) {
        activeProtocols.push('AAVE');
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
        activeProtocols.push('COMPOUND');
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
        activeProtocols.push('MORPHO');
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

      // Disable stale adapter rows for protocols we actively manage from config.
      if (activeProtocols.length > 0) {
        const expectedAdapters = adapterRows
          .map((row) => row.adapterAddress)
          .filter((value): value is string => typeof value === 'string');

        if (expectedAdapters.length > 0) {
          await this.protocolAdapterRepository.update(
            {
              chainId: chain.chainId,
              protocol: In(activeProtocols),
              adapterAddress: Not(In(expectedAdapters)),
            },
            {
              isEnabled: false,
            },
          );
        }
      }
    }
  }

  private loadChainContractsConfig(chainKey: SupportedChainKey): ChainContractsConfig {
    const filePath = resolveContractsConfigFilePath(
      this.configService,
      `${chainKey}.json`,
    );
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as ChainContractsConfig;
  }

  private async ethCall(
    rpcUrl: string,
    to: string,
    data: string,
  ): Promise<string> {
    const payload = {
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'eth_call',
      params: [
        {
          to,
          data,
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
    const dataJson = (await response.json()) as {
      result?: string;
      error?: { message?: string };
    };
    if (dataJson.error) {
      throw new Error(`RPC eth_call failed: ${dataJson.error.message ?? 'unknown error'}`);
    }
    if (!dataJson.result || typeof dataJson.result !== 'string') {
      throw new Error('RPC eth_call returned invalid result');
    }
    return dataJson.result;
  }

  private async readTokenDecimals(
    rpcUrl: string,
    tokenAddress: string,
    cache: Map<string, number>,
    cacheKey: string,
    fallbackDecimals: number,
  ): Promise<number> {
    const cached = cache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }

    try {
      const calldata = this.erc20MetadataInterface.encodeFunctionData('decimals', []);
      const rawResult = await this.ethCall(rpcUrl, tokenAddress, calldata);
      const decoded = this.erc20MetadataInterface.decodeFunctionResult(
        'decimals',
        rawResult,
      );
      const decimals = decoded[0];
      const resolved = Number(decimals);
      cache.set(cacheKey, resolved);
      return resolved;
    } catch {
      cache.set(cacheKey, fallbackDecimals);
      return fallbackDecimals;
    }
  }

  private async readOraclePriceWad(
    rpcUrl: string,
    oracleAddress: string,
    assetAddress: string,
    cache: Map<string, bigint>,
    cacheKey: string,
  ): Promise<bigint> {
    const cached = cache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }

    const calldata = this.oracleInterface.encodeFunctionData('getPrice', [assetAddress]);
    const rawResult = await this.ethCall(rpcUrl, oracleAddress, calldata);
    const decoded = this.oracleInterface.decodeFunctionResult('getPrice', rawResult);
    const price = decoded[0] as bigint;
    cache.set(cacheKey, price);
    return price;
  }

  private computeHealthFactorWad(params: {
    collateralAmountRaw: bigint;
    debtAmountRaw: bigint;
    collateralPriceWad: bigint;
    debtPriceWad: bigint;
    collateralDecimals: number;
    debtDecimals: number;
    liquidationThresholdBps: number;
  }): bigint {
    const {
      collateralAmountRaw,
      debtAmountRaw,
      collateralPriceWad,
      debtPriceWad,
      collateralDecimals,
      debtDecimals,
      liquidationThresholdBps,
    } = params;

    if (debtAmountRaw <= 0n) {
      return MAX_UINT256;
    }
    if (debtPriceWad <= 0n || collateralPriceWad <= 0n) {
      return 0n;
    }

    const collateralDenominator = 10n ** BigInt(collateralDecimals);
    const debtDenominator = 10n ** BigInt(debtDecimals);

    const collateralUsdWad =
      (collateralAmountRaw * collateralPriceWad) / collateralDenominator;
    const debtUsdWad = (debtAmountRaw * debtPriceWad) / debtDenominator;
    if (debtUsdWad <= 0n) {
      return MAX_UINT256;
    }

    const effectiveCollateralUsdWad =
      (collateralUsdWad * BigInt(liquidationThresholdBps)) / 10_000n;
    return (effectiveCollateralUsdWad * WAD) / debtUsdWad;
  }

  private toSimPosition(position: {
    chainId: number;
    chainKey: string;
    protocol: string;
    adapterAddress: string;
    collateralAsset: string;
    debtAsset: string;
    collateralAmountRaw: string;
    debtAmountRaw: string;
    healthFactorWad: string;
    liquidationThresholdBps: number | null;
    collateralDecimals: number;
    debtDecimals: number;
    collateralPriceWad: string | null;
    debtPriceWad: string | null;
  }): SimPosition {
    return {
      chainId: position.chainId,
      chainKey: position.chainKey,
      protocol: position.protocol,
      adapterAddress: position.adapterAddress.toLowerCase(),
      collateralAsset: position.collateralAsset.toLowerCase(),
      debtAsset: position.debtAsset.toLowerCase(),
      collateralAmountRaw: BigInt(position.collateralAmountRaw),
      debtAmountRaw: BigInt(position.debtAmountRaw),
      healthFactorWad: BigInt(position.healthFactorWad),
      liquidationThresholdBps: BigInt(position.liquidationThresholdBps ?? 8000),
      collateralDecimals: position.collateralDecimals,
      debtDecimals: position.debtDecimals,
      collateralPriceWad: position.collateralPriceWad
        ? BigInt(position.collateralPriceWad)
        : null,
      debtPriceWad: position.debtPriceWad ? BigInt(position.debtPriceWad) : null,
    };
  }

  private flattenPositions(positions: SimPosition[]): FlatPosition[] {
    const byAdapter = new Map<string, bigint>();
    for (const position of positions) {
      const key = `${position.chainId}:${position.adapterAddress}`;
      byAdapter.set(
        key,
        (byAdapter.get(key) ?? 0n) + position.collateralAmountRaw,
      );
    }

    return positions.map((position) => {
      const key = `${position.chainId}:${position.adapterAddress}`;
      return {
        label: `${position.protocol.toLowerCase()}-${position.chainKey}`,
        adapterAddress: position.adapterAddress,
        availableCollateral: byAdapter.get(key) ?? 0n,
        chainId: position.chainId,
        chainKey: position.chainKey,
        position,
      };
    });
  }

  private buildDecimalsMap(positions: SimPosition[]): Map<string, number> {
    const map = new Map<string, number>();
    for (const position of positions) {
      map.set(position.collateralAsset, position.collateralDecimals);
      map.set(position.debtAsset, position.debtDecimals);
    }
    return map;
  }

  private buildPriceMap(positions: SimPosition[]): Map<string, bigint> {
    const map = new Map<string, bigint>();
    for (const position of positions) {
      if (position.collateralPriceWad && position.collateralPriceWad > 0n) {
        map.set(position.collateralAsset, position.collateralPriceWad);
      }
      if (position.debtPriceWad && position.debtPriceWad > 0n) {
        map.set(position.debtAsset, position.debtPriceWad);
      }
    }
    return map;
  }

  private bpsToWad(bps: number): bigint {
    return BigInt(Math.max(0, Math.trunc(bps))) * 10n ** 14n;
  }

  private decideRoute(
    weakestEffectiveHfWad: bigint,
    minHfWad: bigint,
    earlyHfWad: bigint,
    allowCrossChain: boolean,
    canCrossChain: boolean,
  ): Decision {
    if (weakestEffectiveHfWad <= minHfWad || weakestEffectiveHfWad <= earlyHfWad) {
      if (allowCrossChain && canCrossChain) {
        return 'RESCUE_CROSS_CHAIN';
      }
      return 'RESCUE_SAME_CHAIN';
    }
    return 'NO_ACTION';
  }

  private minBigInt(a: bigint, b: bigint): bigint {
    return a < b ? a : b;
  }

  private toUsdWad(amount: bigint, decimals: number, priceUsdWad: bigint): bigint {
    if (amount <= 0n || priceUsdWad <= 0n) return 0n;
    return (amount * priceUsdWad) / 10n ** BigInt(decimals);
  }

  private fromUsdWadToAmount(
    usdWad: bigint,
    decimals: number,
    priceUsdWad: bigint,
  ): bigint {
    if (usdWad <= 0n || priceUsdWad <= 0n) return 0n;
    return (usdWad * 10n ** BigInt(decimals)) / priceUsdWad;
  }

  private wadToFixed(wad: bigint, fractionDigits = 4): string {
    const sign = wad < 0n ? '-' : '';
    const abs = wad < 0n ? -wad : wad;
    const whole = abs / WAD;
    if (fractionDigits <= 0) return `${sign}${whole.toString()}`;
    const fracBase = 10n ** BigInt(18 - fractionDigits);
    const frac = (abs % WAD) / fracBase;
    return `${sign}${whole.toString()}.${frac.toString().padStart(fractionDigits, '0')}`;
  }

  private formatHf(hfWad: bigint): string {
    if (hfWad >= MAX_UINT256 / 2n) return 'INF';
    return this.wadToFixed(hfWad, 4);
  }

  private canonicalAsset(asset: string, canonicalMap: Map<string, string>): string {
    const key = asset.toLowerCase();
    return canonicalMap.get(key) ?? key;
  }

  private inferRescueModeFromPositions(
    source: FlatPosition,
    target: FlatPosition,
    canonicalMap: Map<string, string>,
  ): RescueMode | undefined {
    const srcCollateral = this.canonicalAsset(
      source.position.collateralAsset,
      canonicalMap,
    );
    const srcDebt = this.canonicalAsset(source.position.debtAsset, canonicalMap);
    const tgtCollateral = this.canonicalAsset(
      target.position.collateralAsset,
      canonicalMap,
    );
    const tgtDebt = this.canonicalAsset(target.position.debtAsset, canonicalMap);

    if (srcCollateral === tgtCollateral && srcDebt === tgtDebt) {
      return 'TOP_UP';
    }
    if (srcCollateral === tgtDebt && srcDebt === tgtCollateral) {
      return 'REPAY';
    }
    if (srcCollateral === tgtDebt) {
      return 'REPAY';
    }
    if (srcCollateral === tgtCollateral) {
      return 'TOP_UP';
    }
    return undefined;
  }

  private estimateNeededAction(
    mode: RescueMode,
    target: FlatPosition,
    targetHfBps: number,
    getPriceWad: (asset: string) => bigint | undefined,
    getDecimals: (asset: string) => number,
  ): bigint {
    const collateralPriceWad = getPriceWad(target.position.collateralAsset);
    const debtPriceWad = getPriceWad(target.position.debtAsset);
    const collateralDecimals = getDecimals(target.position.collateralAsset);
    const debtDecimals = getDecimals(target.position.debtAsset);
    const targetHfWad = BigInt(targetHfBps) * 10n ** 14n;

    if (!collateralPriceWad || !debtPriceWad || targetHfWad === 0n) {
      return mode === 'TOP_UP'
        ? target.position.collateralAmountRaw / 10n
        : target.position.debtAmountRaw / 5n;
    }

    const collateralUsdWad = this.toUsdWad(
      target.position.collateralAmountRaw,
      collateralDecimals,
      collateralPriceWad,
    );
    const debtUsdWad = this.toUsdWad(
      target.position.debtAmountRaw,
      debtDecimals,
      debtPriceWad,
    );
    const effectiveCollateralUsdWad =
      (collateralUsdWad * target.position.liquidationThresholdBps) / BPS_DENOM;

    if (mode === 'TOP_UP') {
      const wantedEffectiveCollateralUsdWad = (targetHfWad * debtUsdWad) / WAD;
      if (wantedEffectiveCollateralUsdWad <= effectiveCollateralUsdWad) return 0n;
      const deltaEffectiveUsdWad =
        wantedEffectiveCollateralUsdWad - effectiveCollateralUsdWad;
      if (target.position.liquidationThresholdBps === 0n) return 0n;
      const deltaCollateralUsdWad =
        (deltaEffectiveUsdWad * BPS_DENOM) /
        target.position.liquidationThresholdBps;
      return this.fromUsdWadToAmount(
        deltaCollateralUsdWad,
        collateralDecimals,
        collateralPriceWad,
      );
    }

    const maxDebtUsdAtTarget = (effectiveCollateralUsdWad * WAD) / targetHfWad;
    if (debtUsdWad <= maxDebtUsdAtTarget) return 0n;
    const debtReductionUsdWad = debtUsdWad - maxDebtUsdAtTarget;
    return this.fromUsdWadToAmount(
      debtReductionUsdWad,
      debtDecimals,
      debtPriceWad,
    );
  }

  private computeSourceHfSafeCap(
    source: FlatPosition,
    sourceFloorHfBps: number,
    getPriceWad: (asset: string) => bigint | undefined,
    getDecimals: (asset: string) => number,
  ): bigint {
    if (sourceFloorHfBps <= 0) {
      return source.availableCollateral;
    }

    const sourcePrice = getPriceWad(source.position.collateralAsset);
    const sourceDebtPrice = getPriceWad(source.position.debtAsset);
    if (!sourcePrice || !sourceDebtPrice || source.position.debtAmountRaw <= 0n) {
      return source.availableCollateral;
    }

    const sourceCollDecimals = getDecimals(source.position.collateralAsset);
    const sourceDebtDecimals = getDecimals(source.position.debtAsset);
    const sourceCollUsdWad = this.toUsdWad(
      source.position.collateralAmountRaw,
      sourceCollDecimals,
      sourcePrice,
    );
    const sourceDebtUsdWad = this.toUsdWad(
      source.position.debtAmountRaw,
      sourceDebtDecimals,
      sourceDebtPrice,
    );
    const sourceEffectiveCollUsdWad =
      (sourceCollUsdWad * source.position.liquidationThresholdBps) / BPS_DENOM;
    const floorHfWad = BigInt(sourceFloorHfBps) * 10n ** 14n;
    const minEffectiveCollAtFloorUsdWad = (floorHfWad * sourceDebtUsdWad) / WAD;

    if (
      source.position.liquidationThresholdBps === 0n ||
      sourceEffectiveCollUsdWad <= minEffectiveCollAtFloorUsdWad
    ) {
      return 0n;
    }

    const headroomEffectiveUsdWad =
      sourceEffectiveCollUsdWad - minEffectiveCollAtFloorUsdWad;
    const headroomCollateralUsdWad =
      (headroomEffectiveUsdWad * BPS_DENOM) /
      source.position.liquidationThresholdBps;
    return this.fromUsdWadToAmount(
      headroomCollateralUsdWad,
      sourceCollDecimals,
      sourcePrice,
    );
  }

  private resolveChainSelectorByChainId(chainId: number): string {
    const chainKey = this.resolveChainKeyFromChainId(chainId);
    const chain = this.chainRegistryService.getByKey(chainKey);
    return chain.ccipSelector;
  }

  private prettyChainLabel(chainKey: string): string {
    const normalized = chainKey.toLowerCase();
    if (normalized.includes('ethereum')) return 'eth sepolia';
    if (normalized.includes('base')) return 'base sepolia';
    return chainKey.replace(/-/g, ' ');
  }

  private async buildCanonicalAssetMap(
    positions: SimPosition[],
  ): Promise<Map<string, string>> {
    const canonical = new Map<string, string>();
    const assetsByChain = new Map<number, Set<string>>();
    for (const position of positions) {
      const collateral = position.collateralAsset.toLowerCase();
      const debt = position.debtAsset.toLowerCase();
      canonical.set(collateral, collateral);
      canonical.set(debt, debt);
      if (!assetsByChain.has(position.chainId)) {
        assetsByChain.set(position.chainId, new Set<string>());
      }
      assetsByChain.get(position.chainId)?.add(collateral);
      assetsByChain.get(position.chainId)?.add(debt);
    }

    try {
      const ethConfig = this.loadChainContractsConfig('ethereum-sepolia');
      const baseConfig = this.loadChainContractsConfig('base-sepolia');
      const ethCollateral = (ethConfig.contracts?.MockERC20_Collateral ?? '').toLowerCase();
      const ethDebt = (ethConfig.contracts?.MockERC20_Debt ?? '').toLowerCase();
      const baseCollateral = (baseConfig.contracts?.MockERC20_Collateral ?? '').toLowerCase();
      const baseDebt = (baseConfig.contracts?.MockERC20_Debt ?? '').toLowerCase();

      if (ethCollateral && baseCollateral) {
        canonical.set(baseCollateral, ethCollateral);
      }
      if (ethDebt && baseDebt) {
        canonical.set(baseDebt, ethDebt);
      }
    } catch {
      // best effort canonicalization
    }

    const symbolGroups = new Map<string, Array<{ asset: string; chainId: number }>>();
    const symbolCache = new Map<string, string>();
    for (const [chainId, assets] of assetsByChain.entries()) {
      const rpcUrl = this.chainRegistryService.getByKey(
        this.resolveChainKeyFromChainId(chainId),
      ).rpcUrl;
      for (const asset of assets) {
        const symbol = await this.readTokenSymbol(
          rpcUrl,
          asset,
          symbolCache,
          `${chainId}:${asset}`,
        );
        if (!symbol || symbol.length === 0) continue;
        const key = symbol.toUpperCase();
        const group = symbolGroups.get(key) ?? [];
        group.push({ asset, chainId });
        symbolGroups.set(key, group);
      }
    }

    for (const group of symbolGroups.values()) {
      if (group.length < 2) continue;
      const preferred =
        group.find((item) => item.chainId === 11155111)?.asset ?? group[0].asset;
      for (const entry of group) {
        canonical.set(entry.asset, preferred);
      }
    }

    return canonical;
  }

  private buildCanonicalAssetMapFromChainConfigs(): Map<string, string> {
    const canonical = new Map<string, string>();
    try {
      const ethConfig = this.loadChainContractsConfig('ethereum-sepolia');
      const baseConfig = this.loadChainContractsConfig('base-sepolia');
      const ethCollateral = (
        ethConfig.contracts?.MockERC20_Collateral ?? ''
      ).toLowerCase();
      const ethDebt = (ethConfig.contracts?.MockERC20_Debt ?? '').toLowerCase();
      const baseCollateral = (
        baseConfig.contracts?.MockERC20_Collateral ?? ''
      ).toLowerCase();
      const baseDebt = (baseConfig.contracts?.MockERC20_Debt ?? '').toLowerCase();

      if (ethCollateral) canonical.set(ethCollateral, ethCollateral);
      if (ethDebt) canonical.set(ethDebt, ethDebt);
      if (baseCollateral) canonical.set(baseCollateral, baseCollateral);
      if (baseDebt) canonical.set(baseDebt, baseDebt);

      if (baseCollateral && ethCollateral) canonical.set(baseCollateral, ethCollateral);
      if (baseDebt && ethDebt) canonical.set(baseDebt, ethDebt);
    } catch {
      // best effort only
    }
    return canonical;
  }

  private async readTokenSymbol(
    rpcUrl: string,
    tokenAddress: string,
    cache: Map<string, string>,
    cacheKey: string,
  ): Promise<string | undefined> {
    const cached = cache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }

    try {
      const calldata =
        this.erc20SymbolStringInterface.encodeFunctionData('symbol', []);
      const rawResult = await this.ethCall(rpcUrl, tokenAddress, calldata);
      const decoded = this.erc20SymbolStringInterface.decodeFunctionResult(
        'symbol',
        rawResult,
      );
      const value = String(decoded[0] ?? '').trim();
      cache.set(cacheKey, value);
      return value;
    } catch {
      try {
        const calldata =
          this.erc20SymbolBytes32Interface.encodeFunctionData('symbol', []);
        const rawResult = await this.ethCall(rpcUrl, tokenAddress, calldata);
        const decoded = this.erc20SymbolBytes32Interface.decodeFunctionResult(
          'symbol',
          rawResult,
        );
        const rawHex = String(decoded[0] ?? '');
        const bytes = Buffer.from(rawHex.replace(/^0x/, ''), 'hex');
        const value = bytes.toString('utf8').replace(/\u0000/g, '').trim();
        cache.set(cacheKey, value);
        return value;
      } catch {
        cache.set(cacheKey, '');
        return undefined;
      }
    }
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
