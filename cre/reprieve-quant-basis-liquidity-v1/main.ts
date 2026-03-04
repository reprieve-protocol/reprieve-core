import { Runner, type Runtime, type EVMLog, type CronPayload } from "@chainlink/cre-sdk";
import {
  type ChainlinkApiGuardConfig,
  type QuantBasisLiquidityConfig,
  buildEnvelope,
  parseProfileWorkflowConfig,
} from "./types";
import {
  parseHttpInput,
  registerBaseTriggers,
  resolveCronTimestampSeconds,
  safeJson,
} from "./runtime";
import {
  reconcileChainlinkApiGuardLog,
  runChainlinkApiGuardFlow,
} from "./lib/full-flow-v1";
import {
  buildBasisLiquidityGuardConfig,
  evaluateBasisLiquiditySignal,
} from "./lib/quant-signal-v1";

const PROFILE_ID = "QUANT_BASIS_LIQUIDITY_V1" as const;

const onHttpTrigger = (runtime: Runtime<QuantBasisLiquidityConfig>, payload: unknown): string => {
  const body = parseHttpInput(payload);
  runtime.log(`[${PROFILE_ID}] HTTP trigger received`);
  const quantSignal = evaluateBasisLiquiditySignal(runtime, body, runtime.config);
  const guardConfig = buildBasisLiquidityGuardConfig(runtime.config, quantSignal);
  const envelope = runChainlinkApiGuardFlow(
    runtime as unknown as Runtime<ChainlinkApiGuardConfig>,
    guardConfig,
    "http",
    body
  );

  return safeJson(
    buildEnvelope({
      ...envelope,
      strategyId: PROFILE_ID,
      metadata: {
        ...envelope.metadata,
        trigger: "http",
        quantDecisionMode: quantSignal.decisionMode,
        quantStressScoreBps: quantSignal.stressScoreBps,
        quantEarlyWarningBoostBps: quantSignal.earlyWarningBoostBps,
        quantAdjustedEarlyWarningHfBps: quantSignal.adjustedEarlyWarningHfBps,
        quantBasisInputBps: quantSignal.basisInputBps,
        quantLiquidityInputBps: quantSignal.liquidityInputBps,
        quantTakerInputBps: quantSignal.takerImbalanceInputBps,
        quantRegimeInputBps: quantSignal.regimeExtremeInputBps,
        quantSeverity: quantSignal.severity,
      },
    })
  );
};

const onEvmLogTrigger = (runtime: Runtime<QuantBasisLiquidityConfig>, payload: EVMLog): string => {
  runtime.log(`[${PROFILE_ID}] EVM log trigger received`);
  const quantSignal = evaluateBasisLiquiditySignal(runtime, {}, runtime.config);
  const guardConfig = buildBasisLiquidityGuardConfig(runtime.config, quantSignal);
  const envelope = reconcileChainlinkApiGuardLog(
    runtime as unknown as Runtime<ChainlinkApiGuardConfig>,
    guardConfig,
    payload
  );

  return safeJson(
    buildEnvelope({
      ...envelope,
      strategyId: PROFILE_ID,
      metadata: {
        ...envelope.metadata,
        trigger: "evm_log",
        quantDecisionMode: quantSignal.decisionMode,
        quantStressScoreBps: quantSignal.stressScoreBps,
      },
    })
  );
};

const onCronTrigger = (runtime: Runtime<QuantBasisLiquidityConfig>, payload: CronPayload): string => {
  runtime.log(`[${PROFILE_ID}] cron trigger at ${resolveCronTimestampSeconds(payload)}`);
  const quantSignal = evaluateBasisLiquiditySignal(runtime, {}, runtime.config);
  const guardConfig = buildBasisLiquidityGuardConfig(runtime.config, quantSignal);
  const envelope = runChainlinkApiGuardFlow(
    runtime as unknown as Runtime<ChainlinkApiGuardConfig>,
    guardConfig,
    "cron",
    {}
  );

  return safeJson(
    buildEnvelope({
      ...envelope,
      strategyId: PROFILE_ID,
      metadata: {
        ...envelope.metadata,
        trigger: "cron",
        quantDecisionMode: quantSignal.decisionMode,
        quantStressScoreBps: quantSignal.stressScoreBps,
        quantEarlyWarningBoostBps: quantSignal.earlyWarningBoostBps,
        quantAdjustedEarlyWarningHfBps: quantSignal.adjustedEarlyWarningHfBps,
      },
    })
  );
};

const initWorkflow = (rawConfig: QuantBasisLiquidityConfig) => {
  const parsed = parseProfileWorkflowConfig(
    rawConfig,
    PROFILE_ID
  ) as QuantBasisLiquidityConfig;

  return registerBaseTriggers(parsed, {
    onHttp: onHttpTrigger,
    onEvmLog: onEvmLogTrigger,
    onCron: onCronTrigger,
  });
};

export async function main() {
  const runner = await Runner.newRunner<QuantBasisLiquidityConfig>();
  await runner.run(initWorkflow);
}

main();
