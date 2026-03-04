import type { Runtime } from "@chainlink/cre-sdk";
import type {
  ChainlinkApiGuardConfig,
  QuantBasisLiquidityConfig,
} from "../types";

type QuantDecisionMode = "APPLY" | "LOG_ONLY";

export type BasisLiquiditySignal = {
  decisionMode: QuantDecisionMode;
  basisInputBps: number;
  liquidityInputBps: number;
  takerImbalanceInputBps: number;
  regimeExtremeInputBps: number;
  stressScoreBps: number;
  earlyWarningBoostBps: number;
  adjustedEarlyWarningHfBps: number;
  severity: "LOW" | "MEDIUM" | "HIGH";
};

const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, value));

const toNumber = (value: unknown): number | undefined => {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
};

const readAbsBps = (value: unknown, fallback: number): number => {
  const parsed = toNumber(value);
  if (parsed === undefined) return Math.abs(Math.trunc(fallback));
  return Math.abs(Math.trunc(parsed));
};

const readDecisionMode = (raw: unknown): QuantDecisionMode => {
  if (typeof raw !== "string") return "APPLY";
  const normalized = raw.trim().toUpperCase();
  if (normalized === "LOG_ONLY") return "LOG_ONLY";
  return "APPLY";
};

export const evaluateBasisLiquiditySignal = (
  runtime: Runtime<QuantBasisLiquidityConfig>,
  body: Record<string, unknown>,
  config: QuantBasisLiquidityConfig
): BasisLiquiditySignal => {
  const thresholds = config.thresholds;
  const weights = config.dataSources.quantBasisLiquidity;
  const decisionMode = readDecisionMode(body.quantDecisionMode);

  const basisInputBps = readAbsBps(
    body.mockBasisStressBps ?? body.basisStressBps ?? body.basisBps,
    Math.floor(thresholds.basisStressBps * 0.7)
  );
  const liquidityInputBps = readAbsBps(
    body.mockLiquidityStressBps ?? body.liquidityStressBps ?? body.depthStressBps,
    Math.floor(thresholds.liquidityStressBps * 0.7)
  );
  const takerImbalanceInputBps = readAbsBps(
    body.mockTakerImbalanceBps ?? body.takerImbalanceBps ?? body.takerFlowBps,
    Math.floor(thresholds.takerImbalanceBps * 0.7)
  );
  const regimeExtremeInputBps = readAbsBps(
    body.mockRegimeExtremeBps ?? body.regimeExtremeBps ?? body.regimeBps,
    Math.floor(thresholds.regimeExtremeBps * 0.7)
  );

  const weighted =
    basisInputBps * weights.basisWeightBps +
    liquidityInputBps * weights.liquidityWeightBps +
    takerImbalanceInputBps * weights.takerFlowWeightBps;
  const stressScoreBps = Math.floor(weighted / 10000) + Math.floor(regimeExtremeInputBps / 4);
  const applyFactorBps = decisionMode === "APPLY" ? 4500 : 0;
  const earlyWarningBoostBps = Math.floor((stressScoreBps * applyFactorBps) / 10000);
  const adjustedEarlyWarningHfBps = clamp(
    thresholds.earlyWarningHfBps + earlyWarningBoostBps,
    thresholds.onchainHfMinBps,
    20000
  );

  const severity: BasisLiquiditySignal["severity"] =
    stressScoreBps >= Math.max(thresholds.basisStressBps, thresholds.liquidityStressBps)
      ? "HIGH"
      : stressScoreBps >= Math.floor(Math.max(thresholds.basisStressBps, thresholds.liquidityStressBps) / 2)
      ? "MEDIUM"
      : "LOW";

  runtime.log(
    `[QUANT_BASIS_LIQUIDITY_V1][signal] mode=${decisionMode} basisStressBps=${basisInputBps} liquidityStressBps=${liquidityInputBps} takerImbalanceBps=${takerImbalanceInputBps} regimeExtremeBps=${regimeExtremeInputBps}`
  );
  runtime.log(
    `[QUANT_BASIS_LIQUIDITY_V1][signal] weights basis=${weights.basisWeightBps} liquidity=${weights.liquidityWeightBps} takerFlow=${weights.takerFlowWeightBps} stressScoreBps=${stressScoreBps} severity=${severity}`
  );
  runtime.log(
    `[QUANT_BASIS_LIQUIDITY_V1][signal] earlyWarning base=${thresholds.earlyWarningHfBps} boost=${earlyWarningBoostBps} adjusted=${adjustedEarlyWarningHfBps}`
  );

  return {
    decisionMode,
    basisInputBps,
    liquidityInputBps,
    takerImbalanceInputBps,
    regimeExtremeInputBps,
    stressScoreBps,
    earlyWarningBoostBps,
    adjustedEarlyWarningHfBps,
    severity,
  };
};

export const buildBasisLiquidityGuardConfig = (
  config: QuantBasisLiquidityConfig,
  signal: BasisLiquiditySignal
): ChainlinkApiGuardConfig => ({
  ...(config as unknown as ChainlinkApiGuardConfig),
  strategyId: "CHAINLINK_API_GUARD_V1",
  thresholds: {
    onchainHfMinBps: config.thresholds.onchainHfMinBps,
    earlyWarningHfBps: signal.adjustedEarlyWarningHfBps,
    stalePricePenaltyBps: 0,
    slopePenaltyBps: 0,
  },
  monitoring: config.monitoring,
});
