import type { Runtime } from "@chainlink/cre-sdk";
import type {
  ChainlinkApiGuardConfig,
  QuantFundingOiConfig,
} from "../types";

type QuantDecisionMode = "APPLY" | "LOG_ONLY";

export type FundingOiSignal = {
  decisionMode: QuantDecisionMode;
  fundingInputBps: number;
  oiInputBps: number;
  venueDivergenceInputBps: number;
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

export const evaluateFundingOiSignal = (
  runtime: Runtime<QuantFundingOiConfig>,
  body: Record<string, unknown>,
  config: QuantFundingOiConfig
): FundingOiSignal => {
  const thresholds = config.thresholds;
  const weights = config.dataSources.quantFundingOi;
  const decisionMode = readDecisionMode(body.quantDecisionMode);

  const fundingInputBps = readAbsBps(
    body.mockFundingStressBps ?? body.fundingStressBps ?? body.fundingBps,
    Math.floor(thresholds.fundingStressBps * 0.7)
  );
  const oiInputBps = readAbsBps(
    body.mockOiStressBps ?? body.oiStressBps ?? body.oiBps,
    Math.floor(thresholds.oiStressBps * 0.7)
  );
  const venueDivergenceInputBps = readAbsBps(
    body.mockVenueDivergenceBps ?? body.venueDivergenceBps ?? body.divergenceBps,
    Math.floor(thresholds.venueDivergencePenaltyBps * 0.7)
  );

  const weighted =
    fundingInputBps * weights.fundingWeightBps +
    oiInputBps * weights.oiWeightBps +
    venueDivergenceInputBps * weights.divergenceWeightBps;
  const stressScoreBps = Math.floor(weighted / 10000);
  const applyFactorBps = decisionMode === "APPLY" ? 4500 : 0;
  const earlyWarningBoostBps = Math.floor((stressScoreBps * applyFactorBps) / 10000);
  const adjustedEarlyWarningHfBps = clamp(
    thresholds.earlyWarningHfBps + earlyWarningBoostBps,
    thresholds.onchainHfMinBps,
    20000
  );

  const severity: FundingOiSignal["severity"] =
    stressScoreBps >= Math.max(thresholds.fundingStressBps, thresholds.oiStressBps)
      ? "HIGH"
      : stressScoreBps >= Math.floor(Math.max(thresholds.fundingStressBps, thresholds.oiStressBps) / 2)
      ? "MEDIUM"
      : "LOW";

  runtime.log(
    `[QUANT_FUNDING_OI_V1][signal] mode=${decisionMode} fundingStressBps=${fundingInputBps} oiStressBps=${oiInputBps} venueDivergenceBps=${venueDivergenceInputBps}`
  );
  runtime.log(
    `[QUANT_FUNDING_OI_V1][signal] weights funding=${weights.fundingWeightBps} oi=${weights.oiWeightBps} divergence=${weights.divergenceWeightBps} stressScoreBps=${stressScoreBps} severity=${severity}`
  );
  runtime.log(
    `[QUANT_FUNDING_OI_V1][signal] earlyWarning base=${thresholds.earlyWarningHfBps} boost=${earlyWarningBoostBps} adjusted=${adjustedEarlyWarningHfBps}`
  );

  return {
    decisionMode,
    fundingInputBps,
    oiInputBps,
    venueDivergenceInputBps,
    stressScoreBps,
    earlyWarningBoostBps,
    adjustedEarlyWarningHfBps,
    severity,
  };
};

export const buildFundingOiGuardConfig = (
  config: QuantFundingOiConfig,
  signal: FundingOiSignal
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
