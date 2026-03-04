import { Runner, type Runtime, type EVMLog, type CronPayload } from "@chainlink/cre-sdk";
import {
  type ChainlinkApiGuardConfig,
  type QuantFundingOiConfig,
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
  buildFundingOiGuardConfig,
  evaluateFundingOiSignal,
} from "./lib/quant-signal-v1";

const PROFILE_ID = "QUANT_FUNDING_OI_V1" as const;

const onHttpTrigger = (runtime: Runtime<QuantFundingOiConfig>, payload: unknown): string => {
  const body = parseHttpInput(payload);
  runtime.log(`[${PROFILE_ID}] HTTP trigger received`);
  const quantSignal = evaluateFundingOiSignal(runtime, body, runtime.config);
  const guardConfig = buildFundingOiGuardConfig(runtime.config, quantSignal);
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
        quantFundingInputBps: quantSignal.fundingInputBps,
        quantOiInputBps: quantSignal.oiInputBps,
        quantDivergenceInputBps: quantSignal.venueDivergenceInputBps,
        quantSeverity: quantSignal.severity,
      },
    })
  );
};

const onEvmLogTrigger = (runtime: Runtime<QuantFundingOiConfig>, payload: EVMLog): string => {
  runtime.log(`[${PROFILE_ID}] EVM log trigger received`);
  const quantSignal = evaluateFundingOiSignal(runtime, {}, runtime.config);
  const guardConfig = buildFundingOiGuardConfig(runtime.config, quantSignal);
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

const onCronTrigger = (runtime: Runtime<QuantFundingOiConfig>, payload: CronPayload): string => {
  runtime.log(`[${PROFILE_ID}] cron trigger at ${resolveCronTimestampSeconds(payload)}`);
  const quantSignal = evaluateFundingOiSignal(runtime, {}, runtime.config);
  const guardConfig = buildFundingOiGuardConfig(runtime.config, quantSignal);
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

const initWorkflow = (rawConfig: QuantFundingOiConfig) => {
  const parsed = parseProfileWorkflowConfig(
    rawConfig,
    PROFILE_ID
  ) as QuantFundingOiConfig;

  return registerBaseTriggers(parsed, {
    onHttp: onHttpTrigger,
    onEvmLog: onEvmLogTrigger,
    onCron: onCronTrigger,
  });
};

export async function main() {
  const runner = await Runner.newRunner<QuantFundingOiConfig>();
  await runner.run(initWorkflow);
}

main();
