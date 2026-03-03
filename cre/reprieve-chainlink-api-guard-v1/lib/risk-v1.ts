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
  readMockOraclePrice,
  readTokenDecimals,
  type AdapterPosition,
} from "./contracts";

const WAD = 10n ** 18n;
const BPS_DENOM = 10000n;
const MAX_PENALTY_BPS = 9000n;
const MAX_HF_WAD = (2n ** 255n) - 1n;

type PriceReport = {
  asset: Address;
  priceUsd: string;
  updatedAt: number;
  prevPriceUsd?: string;
  integrityHash?: string;
  source: "api" | "oracle" | "mock";
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

const formatUnits = (value: bigint, decimals: number, fractionDigits = 4): string => {
  const sign = value < 0n ? "-" : "";
  const abs = value < 0n ? -value : value;
  const base = 10n ** BigInt(decimals);
  const whole = abs / base;
  const fractionRaw = abs % base;

  if (fractionDigits <= 0) {
    return `${sign}${whole.toString()}`;
  }

  const padded = fractionRaw.toString().padStart(decimals, "0");
  const sliced = padded.slice(0, Math.min(fractionDigits, decimals));
  const trimmed = sliced.replace(/0+$/, "");
  if (trimmed.length === 0) {
    return `${sign}${whole.toString()}`;
  }
  return `${sign}${whole.toString()}.${trimmed}`;
};

const formatHf = (hfWad: bigint): string => {
  if (hfWad >= MAX_HF_WAD / 2n) {
    return "INF";
  }
  return formatUnits(hfWad, 18, 4);
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
  chain: { chainSelectorName: string; isTestnet: boolean },
  assets: Address[]
): PriceReport[] => {
  const onchainOracle = config.dataSources.chainlinkApi.mockOracleAddress as Address | undefined;
  const preferOnchainOracle = config.dataSources.chainlinkApi.preferOnchainOracle ?? false;

  const loadOnchainOracleReports = (): PriceReport[] => {
    if (!onchainOracle) return [];
    const reports: PriceReport[] = [];
    for (const asset of assets) {
      try {
        const { priceWad, updatedAt } = readMockOraclePrice(runtime, chain, onchainOracle, asset);

        runtime.log(`On-chain oracle read for ${asset}: price=${formatUnits(priceWad, 18)} updatedAt=${updatedAt}`
        );
        if (priceWad <= 0n || updatedAt <= 0) {
          continue;
        }
        reports.push({
          asset: asset.toLowerCase() as Address,
          priceUsd: formatUnits(priceWad, 18, 8),
          updatedAt,
          source: "oracle",
        });
      } catch (error) {
        runtime.log(
          `On-chain oracle read failed for ${asset}: ${error instanceof Error ? error.message : String(error)
          }`
        );
      }
    }
    return reports;
  };

  const loadApiReportsSafe = (): PriceReport[] => {
    try {
      return loadApiReports(runtime, config, assets);
    } catch (error) {
      runtime.log(`Price API fetch failed: ${error instanceof Error ? error.message : String(error)}`);
      return [];
    }
  };

  const reportMap = new Map<Address, PriceReport>();
  const seedReports = (reports: PriceReport[]) => {
    for (const report of reports) {
      const key = report.asset.toLowerCase() as Address;
      if (!reportMap.has(key)) {
        reportMap.set(key, report);
      }
    }
  };

  if (preferOnchainOracle) {
    seedReports(loadOnchainOracleReports());
    if (reportMap.size < assets.length) {
      seedReports(loadApiReportsSafe());
    }
  } else {
    seedReports(loadApiReportsSafe());
    if (reportMap.size < assets.length) {
      seedReports(loadOnchainOracleReports());
    }
  }

  const nowTs = Math.floor(Date.now() / 1000);
  for (const asset of assets) {
    const key = asset.toLowerCase() as Address;
    if (reportMap.has(key)) continue;
    const priceUsd = config.dataSources.chainlinkApi.mockPricesUsd[asset.toLowerCase()];
    if (priceUsd) {
      reportMap.set(key, {
        asset: key,
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

  return Array.from(reportMap.values());
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
  weakestEffectiveHfWad: bigint,
  config: ChainlinkApiGuardConfig,
  snapshots: AdapterSnapshot[]
): RescueDecision => {
  const minHfWad = bpsToWad(config.thresholds.onchainHfMinBps);
  const earlyHfWad = bpsToWad(config.thresholds.earlyWarningHfBps);
  const prefersCrossChain = snapshots.some((s) => s.preferCrossChain);

  if (weakestEffectiveHfWad <= minHfWad) {
    if (config.rescue.allowCrossChain && prefersCrossChain) {
      return "RESCUE_CROSS_CHAIN";
    }
    return "RESCUE_SAME_CHAIN";
  }

  if (weakestEffectiveHfWad <= earlyHfWad) {
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
    runtime.log("[V1] No positions discovered for monitored adapters.");
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

  const reports = loadReportsWithFallback(runtime, config, chain, Array.from(uniqueAssets));
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
  const maxPriceAgeSec = config.dataSources.chainlinkApi.maxPriceAgeSec;
  const stalenessChecksEnabled = maxPriceAgeSec > 0;

  if (!stalenessChecksEnabled) {
    runtime.log("[V1] Staleness checks disabled (maxPriceAgeSec=0).");
  }

  for (const asset of uniqueAssets) {
    const report = reportMap.get(asset.toLowerCase() as Address);
    if (!report) {
      runtime.log(`[V1][price] missing asset=${asset}`);
      missingPriceCount += 1;
      continue;
    }

    const ageSec = nowSec - report.updatedAt;
    const shock = computeShockBps(report);
    runtime.log(
      `[V1][price] asset=${asset} priceUsd=${report.priceUsd} source=${report.source} ageSec=${ageSec} shockBps=${shock}`
    );
    if (stalenessChecksEnabled && ageSec > maxPriceAgeSec) {
      staleReportCount += 1;
      continue;
    }

    if (report.source === "api") {
      if (!verifyReportIntegrity(report, config.dataSources.chainlinkApi.integritySalt)) {
        invalidReportCount += 1;
        continue;
      }
    }

    const stalenessPenalty = stalenessChecksEnabled
      ? (BigInt(ageSec) * BigInt(config.thresholds.stalePricePenaltyBps)) / BigInt(maxPriceAgeSec)
      : 0n;
    if (stalenessPenalty > maxStalenessPenaltyBps) {
      maxStalenessPenaltyBps = stalenessPenalty;
    }

    if (shock > maxShockBps) {
      maxShockBps = shock;
    }
  }

  if (missingPriceCount > 0 && config.monitoring.abortOnMissingPrice) {
    runtime.log(`[V1] Abort: missing prices for ${missingPriceCount} assets.`);
    return {
      decision: "ABORT",
      reason: `Missing prices for ${missingPriceCount} assets`,
      metadata: { missingPriceCount },
      snapshots,
      priceByAsset,
    };
  }

  if (stalenessChecksEnabled && staleReportCount > 0) {
    runtime.log(`[V1] Abort: stale reports count=${staleReportCount}.`);
    return {
      decision: "ABORT",
      reason: `Stale reports detected: ${staleReportCount}`,
      metadata: { staleReportCount },
      snapshots,
      priceByAsset,
    };
  }

  if (invalidReportCount > 0) {
    runtime.log(`[V1] Abort: integrity verification failures=${invalidReportCount}.`);
    return {
      decision: "ABORT",
      reason: `Integrity verification failed for ${invalidReportCount} reports`,
      metadata: { invalidReportCount },
      snapshots,
      priceByAsset,
    };
  }

  if (maxShockBps >= config.monitoring.priceShockAbortBps) {
    runtime.log(
      `[V1] Abort: max shock ${maxShockBps} bps exceeded threshold ${config.monitoring.priceShockAbortBps} bps.`
    );
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
  let positionsAnalyzed = 0;
  let weakestDebtHfWad = MAX_HF_WAD;
  let weakestPositionLabel = "";
  runtime.log(`[V1] User=${user} adaptersWithPositions=${snapshots.length}`);

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
      const positionHfWad =
        debtUsdWad == 0n ? MAX_HF_WAD : (effectiveCollateralUsdWad * WAD) / debtUsdWad;

      if (debtUsdWad > 0n && positionHfWad < weakestDebtHfWad) {
        weakestDebtHfWad = positionHfWad;
        weakestPositionLabel = snap.label;
      }

      totalEffectiveCollateralUsdWad += effectiveCollateralUsdWad;
      totalDebtUsdWad += debtUsdWad;
      positionsAnalyzed += 1;

      runtime.log(
        `[V1][position] adapter=${snap.label} collAsset=${collateralAsset} debtAsset=${debtAsset} collAmt=${formatUnits(
          p.collateralAmount,
          collateralDecimals,
          4
        )} debtAmt=${formatUnits(p.debtAmount, debtDecimals, 4)} collUsd=${formatUnits(
          collateralUsdWad,
          18,
          2
        )} debtUsd=${formatUnits(debtUsdWad, 18, 2)} effCollUsd=${formatUnits(
          effectiveCollateralUsdWad,
          18,
          2
        )} positionHF=${formatHf(positionHfWad)}`
      );
    }
  }

  const aggregateHfWad =
    totalDebtUsdWad === 0n
      ? MAX_HF_WAD
      : (totalEffectiveCollateralUsdWad * WAD) / totalDebtUsdWad;

  const slopePenaltyBps = BigInt(
    Math.min(config.thresholds.slopePenaltyBps, Math.floor(maxShockBps / 2))
  );

  const totalPenaltyBps =
    maxStalenessPenaltyBps + slopePenaltyBps > MAX_PENALTY_BPS
      ? MAX_PENALTY_BPS
      : maxStalenessPenaltyBps + slopePenaltyBps;

  const effectiveHfWad = (aggregateHfWad * (BPS_DENOM - totalPenaltyBps)) / BPS_DENOM;
  const weakestEffectiveHfWad =
    weakestDebtHfWad >= MAX_HF_WAD / 2n
      ? MAX_HF_WAD
      : (weakestDebtHfWad * (BPS_DENOM - totalPenaltyBps)) / BPS_DENOM;

  const decision = evaluateDecision(weakestEffectiveHfWad, config, snapshots);
  const aggregateHf = formatHf(aggregateHfWad);
  const effectiveHf = formatHf(effectiveHfWad);
  const weakestHf = formatHf(weakestDebtHfWad);
  const weakestEffectiveHf = formatHf(weakestEffectiveHfWad);
  const totalEffectiveCollateralUsd = formatUnits(totalEffectiveCollateralUsdWad, 18, 2);
  const totalDebtUsd = formatUnits(totalDebtUsdWad, 18, 2);

  runtime.log(
    `[V1][summary] positions=${positionsAnalyzed} totalEffectiveCollUsd=${totalEffectiveCollateralUsd} totalDebtUsd=${totalDebtUsd} aggregateHF=${aggregateHf} weakestHF=${weakestHf} stalenessPenaltyBps=${Number(
      maxStalenessPenaltyBps
    )} slopePenaltyBps=${Number(slopePenaltyBps)} effectiveHF=${effectiveHf} weakestEffectiveHF=${weakestEffectiveHf} decision=${decision}`
  );

  return {
    decision,
    reason: `Guard evaluated with weakest effective HF ${weakestEffectiveHf} (aggregate ${effectiveHf})`,
    metadata: {
      user,
      adaptersMonitored: snapshots.length,
      positionsAnalyzed,
      reportsUsed: reports.length,
      aggregateHf,
      effectiveHf,
      weakestHf,
      weakestEffectiveHf,
      weakestPositionLabel,
      totalEffectiveCollateralUsd,
      totalDebtUsd,
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
