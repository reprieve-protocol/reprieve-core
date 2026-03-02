import {
  HTTPClient,
  consensusIdenticalAggregation,
  json,
  ok,
  type NodeRuntime,
  type Runtime,
} from "@chainlink/cre-sdk";
import { keccak256, toBytes, type Address } from "viem";
import type {
  ChainlinkApiGuardConfig,
  RescueDecision,
} from "../types";
import {
  discoverPositions,
  readAvailableCollateral,
  readHealthFactor,
  readTokenDecimals,
  type AdapterPosition,
} from "./contracts";

const WAD = 10n ** 18n;
const BPS_DENOM = 10000n;
const MAX_PENALTY_BPS = 9000n;

type PriceReport = {
  asset: Address;
  priceUsd: string;
  updatedAt: number;
  prevPriceUsd?: string;
  integrityHash?: string;
  source: "api" | "mock";
};

export type ChainlinkV1Evaluation = {
  decision: RescueDecision;
  reason: string;
  metadata: Record<string, string | number | boolean>;
  snapshots: AdapterSnapshot[];
  priceByAsset: Record<string, string>;
};

export type AdapterSnapshot = {
  label: string;
  adapterAddress: Address;
  positions: AdapterPosition[];
  hfWad: bigint;
  availableCollateral: bigint;
  rescueTargetChainSelector?: string;
  preferCrossChain: boolean;
};

type ApiResponseShape = {
  timestamp?: number;
  reports?: Array<{
    asset?: string;
    token?: string;
    priceUsd?: string | number;
    price?: string | number;
    updatedAt?: number;
    timestamp?: number;
    prevPriceUsd?: string | number;
    prevPrice?: string | number;
    integrityHash?: string;
  }>;
  prices?: Record<string, string | number>;
};

export const parseUsdToWad = (value: string): bigint => {
  const trimmed = value.trim();
  if (!/^\d+(\.\d+)?$/.test(trimmed)) {
    throw new Error(`Invalid USD value: ${value}`);
  }
  const [whole, frac = ""] = trimmed.split(".");
  const fracPadded = `${frac}000000000000000000`.slice(0, 18);
  return BigInt(whole) * WAD + BigInt(fracPadded);
};

const bpsToWad = (bps: number): bigint => BigInt(bps) * (10n ** 14n);

const buildIntegrityHash = (
  asset: string,
  priceUsd: string,
  updatedAt: number,
  integritySalt: string
): string => keccak256(toBytes(`${asset.toLowerCase()}|${priceUsd}|${updatedAt}|${integritySalt}`));

const verifyReportIntegrity = (
  report: PriceReport,
  integritySalt: string
): boolean => {
  if (!report.integrityHash) return false;
  const expected = buildIntegrityHash(
    report.asset,
    report.priceUsd,
    report.updatedAt,
    integritySalt
  );
  return expected.toLowerCase() === report.integrityHash.toLowerCase();
};

const normalizeApiReports = (
  raw: unknown,
  fallbackTimestamp: number
): PriceReport[] => {
  const payload = (raw ?? {}) as ApiResponseShape;
  const reportTs = typeof payload.timestamp === "number" ? payload.timestamp : fallbackTimestamp;

  if (Array.isArray(payload.reports)) {
    return payload.reports
      .filter((item) => item && (item.asset || item.token))
      .map((item) => {
        const asset = ((item.asset ?? item.token) || "").toLowerCase() as Address;
        const price = String(item.priceUsd ?? item.price ?? "0");
        const updatedAt = Number(item.updatedAt ?? item.timestamp ?? reportTs);
        const prevPrice = item.prevPriceUsd ?? item.prevPrice;
        return {
          asset,
          priceUsd: price,
          updatedAt,
          prevPriceUsd: prevPrice === undefined ? undefined : String(prevPrice),
          integrityHash: item.integrityHash,
          source: "api" as const,
        };
      });
  }

  if (payload.prices && typeof payload.prices === "object") {
    return Object.entries(payload.prices).map(([asset, price]) => ({
      asset: asset.toLowerCase() as Address,
      priceUsd: String(price),
      updatedAt: reportTs,
      source: "api" as const,
    }));
  }

  return [];
};

const loadApiReports = (
  runtime: Runtime<ChainlinkApiGuardConfig>,
  config: ChainlinkApiGuardConfig,
  assets: Address[]
): PriceReport[] => {
  const query = encodeURIComponent(assets.join(","));
  const url = `${config.dataSources.chainlinkApi.priceApiBaseUrl}${config.dataSources.chainlinkApi.priceApiPath}?assets=${query}`;

  const raw = runtime.runInNodeMode(
    (nodeRuntime: NodeRuntime<ChainlinkApiGuardConfig>) => {
      const client = new HTTPClient();
      const response = client
        .sendRequest(nodeRuntime, {
          url,
          method: "GET",
          headers: {
            "content-type": "application/json",
          },
        })
        .result();

      if (!ok(response)) {
        throw new Error(`Price API failed with status ${response.statusCode}`);
      }

      return json(response) as ApiResponseShape;
    },
    consensusIdenticalAggregation<ApiResponseShape>()
  )().result();

  return normalizeApiReports(raw, Math.floor(Date.now() / 1000));
};

const loadReportsWithFallback = (
  runtime: Runtime<ChainlinkApiGuardConfig>,
  config: ChainlinkApiGuardConfig,
  assets: Address[]
): PriceReport[] => {
  try {
    const fromApi = loadApiReports(runtime, config, assets);
    if (fromApi.length > 0) {
      return fromApi;
    }
  } catch (error) {
    runtime.log(`Price API fetch failed: ${error instanceof Error ? error.message : String(error)}`);
  }

  const nowTs = Math.floor(Date.now() / 1000);
  const fallback: PriceReport[] = [];
  for (const asset of assets) {
    const priceUsd = config.dataSources.chainlinkApi.mockPricesUsd[asset.toLowerCase()];
    if (priceUsd) {
      fallback.push({
        asset,
        priceUsd,
        updatedAt: nowTs,
        source: "mock",
        integrityHash: buildIntegrityHash(
          asset,
          priceUsd,
          nowTs,
          config.dataSources.chainlinkApi.integritySalt
        ),
      });
    }
  }
  return fallback;
};

const computeShockBps = (report: PriceReport): number => {
  if (!report.prevPriceUsd) return 0;
  const nowWad = parseUsdToWad(report.priceUsd);
  const prevWad = parseUsdToWad(report.prevPriceUsd);
  if (prevWad === 0n) return 0;

  const diff = nowWad > prevWad ? nowWad - prevWad : prevWad - nowWad;
  return Number((diff * BPS_DENOM) / prevWad);
};

const evaluateDecision = (
  effectiveHfWad: bigint,
  config: ChainlinkApiGuardConfig,
  snapshots: AdapterSnapshot[]
): RescueDecision => {
  const minHfWad = bpsToWad(config.thresholds.onchainHfMinBps);
  const earlyHfWad = bpsToWad(config.thresholds.earlyWarningHfBps);
  const prefersCrossChain = snapshots.some((s) => s.preferCrossChain);

  if (effectiveHfWad <= minHfWad) {
    if (config.rescue.allowCrossChain && prefersCrossChain) {
      return "RESCUE_CROSS_CHAIN";
    }
    return "RESCUE_SAME_CHAIN";
  }

  if (effectiveHfWad <= earlyHfWad) {
    return "RESCUE_SAME_CHAIN";
  }

  return "NO_ACTION";
};

export const evaluateChainlinkApiGuard = (
  runtime: Runtime<ChainlinkApiGuardConfig>,
  config: ChainlinkApiGuardConfig,
  user: Address
): ChainlinkV1Evaluation => {
  const chain = {
    chainSelectorName: config.chainSelectorName,
    isTestnet: config.isTestnet,
  };

  const snapshots: AdapterSnapshot[] = [];
  const adapterReadErrors: string[] = [];
  for (const adapterCfg of config.monitoring.adapters) {
    const adapterAddress = adapterCfg.adapterAddress as Address;
    let positions: AdapterPosition[] = [];
    let hfWad = 0n;
    let availableCollateral = 0n;

    try {
      positions = discoverPositions(runtime, chain, adapterAddress, user);
      if (positions.length === 0) continue;

      hfWad = readHealthFactor(runtime, chain, adapterAddress, user);
      availableCollateral = readAvailableCollateral(
        runtime,
        chain,
        adapterAddress,
        user,
        positions[0].collateralAsset as Address
      );
    } catch (error) {
      adapterReadErrors.push(
        `${adapterCfg.label}:${error instanceof Error ? error.message : String(error)}`
      );
      continue;
    }

    snapshots.push({
      label: adapterCfg.label,
      adapterAddress,
      positions,
      hfWad,
      availableCollateral,
      rescueTargetChainSelector: adapterCfg.rescueTargetChainSelector,
      preferCrossChain: adapterCfg.preferCrossChain ?? false,
    });
  }

  if (snapshots.length === 0) {
    return {
      decision: "ABORT",
      reason: "No positions found for monitored adapters",
      metadata: {
        user,
        adapterReadErrors: adapterReadErrors.length,
      },
      snapshots: [],
      priceByAsset: {},
    };
  }

  const uniqueAssets = new Set<Address>();
  for (const snap of snapshots) {
    for (const p of snap.positions) {
      uniqueAssets.add(p.collateralAsset as Address);
      uniqueAssets.add(p.debtAsset as Address);
    }
  }

  const reports = loadReportsWithFallback(runtime, config, Array.from(uniqueAssets));
  const priceByAsset: Record<string, string> = {};
  const reportMap = new Map<Address, PriceReport>();
  for (const report of reports) {
    reportMap.set(report.asset.toLowerCase() as Address, report);
    priceByAsset[report.asset.toLowerCase()] = report.priceUsd;
  }

  let missingPriceCount = 0;
  let invalidReportCount = 0;
  let staleReportCount = 0;
  let maxShockBps = 0;
  let maxStalenessPenaltyBps = 0n;
  const nowSec = Math.floor(Date.now() / 1000);

  for (const asset of uniqueAssets) {
    const report = reportMap.get(asset.toLowerCase() as Address);
    if (!report) {
      missingPriceCount += 1;
      continue;
    }

    const ageSec = nowSec - report.updatedAt;
    if (ageSec > config.dataSources.chainlinkApi.maxPriceAgeSec) {
      staleReportCount += 1;
      continue;
    }

    if (report.source === "api") {
      if (!verifyReportIntegrity(report, config.dataSources.chainlinkApi.integritySalt)) {
        invalidReportCount += 1;
        continue;
      }
    }

    const stalenessPenalty = (BigInt(ageSec) * BigInt(config.thresholds.stalePricePenaltyBps)) /
      BigInt(config.dataSources.chainlinkApi.maxPriceAgeSec);
    if (stalenessPenalty > maxStalenessPenaltyBps) {
      maxStalenessPenaltyBps = stalenessPenalty;
    }

    const shock = computeShockBps(report);
    if (shock > maxShockBps) {
      maxShockBps = shock;
    }
  }

  if (missingPriceCount > 0 && config.monitoring.abortOnMissingPrice) {
    return {
      decision: "ABORT",
      reason: `Missing prices for ${missingPriceCount} assets`,
      metadata: { missingPriceCount },
      snapshots,
      priceByAsset,
    };
  }

  if (staleReportCount > 0) {
    return {
      decision: "ABORT",
      reason: `Stale reports detected: ${staleReportCount}`,
      metadata: { staleReportCount },
      snapshots,
      priceByAsset,
    };
  }

  if (invalidReportCount > 0) {
    return {
      decision: "ABORT",
      reason: `Integrity verification failed for ${invalidReportCount} reports`,
      metadata: { invalidReportCount },
      snapshots,
      priceByAsset,
    };
  }

  if (maxShockBps >= config.monitoring.priceShockAbortBps) {
    return {
      decision: "ABORT",
      reason: `Price shock exceeded abort threshold (${maxShockBps} bps)`,
      metadata: { maxShockBps, thresholdBps: config.monitoring.priceShockAbortBps },
      snapshots,
      priceByAsset,
    };
  }

  const decimalsCache = new Map<Address, number>();
  let decimalsReadErrors = 0;
  const readDecimalsCached = (asset: Address): number => {
    const key = asset.toLowerCase() as Address;
    const cached = decimalsCache.get(key);
    if (cached !== undefined) return cached;
    let value = 18;
    try {
      value = readTokenDecimals(runtime, chain, key);
    } catch {
      decimalsReadErrors += 1;
    }
    decimalsCache.set(key, value);
    return value;
  };

  let totalEffectiveCollateralUsdWad = 0n;
  let totalDebtUsdWad = 0n;

  for (const snap of snapshots) {
    for (const p of snap.positions) {
      const collateralAsset = (p.collateralAsset as Address).toLowerCase() as Address;
      const debtAsset = (p.debtAsset as Address).toLowerCase() as Address;

      const collateralReport = reportMap.get(collateralAsset);
      const debtReport = reportMap.get(debtAsset);
      if (!collateralReport || !debtReport) {
        continue;
      }

      const collateralPriceWad = parseUsdToWad(collateralReport.priceUsd);
      const debtPriceWad = parseUsdToWad(debtReport.priceUsd);
      const collateralDecimals = readDecimalsCached(collateralAsset);
      const debtDecimals = readDecimalsCached(debtAsset);

      const collateralUsdWad =
        (p.collateralAmount * collateralPriceWad) / (10n ** BigInt(collateralDecimals));
      const debtUsdWad = (p.debtAmount * debtPriceWad) / (10n ** BigInt(debtDecimals));

      const effectiveCollateralUsdWad =
        (collateralUsdWad * p.liquidationThresholdBps) / BPS_DENOM;

      totalEffectiveCollateralUsdWad += effectiveCollateralUsdWad;
      totalDebtUsdWad += debtUsdWad;
    }
  }

  const aggregateHfWad =
    totalDebtUsdWad === 0n
      ? (2n ** 255n) - 1n
      : (totalEffectiveCollateralUsdWad * WAD) / totalDebtUsdWad;

  const slopePenaltyBps = BigInt(
    Math.min(config.thresholds.slopePenaltyBps, Math.floor(maxShockBps / 2))
  );

  const totalPenaltyBps =
    maxStalenessPenaltyBps + slopePenaltyBps > MAX_PENALTY_BPS
      ? MAX_PENALTY_BPS
      : maxStalenessPenaltyBps + slopePenaltyBps;

  const effectiveHfWad = (aggregateHfWad * (BPS_DENOM - totalPenaltyBps)) / BPS_DENOM;

  const decision = evaluateDecision(effectiveHfWad, config, snapshots);

  return {
    decision,
    reason: `Guard evaluated with effective HF ${effectiveHfWad.toString()}`,
    metadata: {
      user,
      adaptersMonitored: snapshots.length,
      reportsUsed: reports.length,
      aggregateHfWad: aggregateHfWad.toString(),
      effectiveHfWad: effectiveHfWad.toString(),
      stalenessPenaltyBps: Number(maxStalenessPenaltyBps),
      slopePenaltyBps: Number(slopePenaltyBps),
      maxShockBps,
      adapterReadErrors: adapterReadErrors.length,
      decimalsReadErrors,
    },
    snapshots,
    priceByAsset,
  };
};

export const __testables = {
  parseUsdToWad,
  buildIntegrityHash,
  verifyReportIntegrity,
  bpsToWad,
  computeShockBps,
};
