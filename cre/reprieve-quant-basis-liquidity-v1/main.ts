import { Runner, type Runtime, type EVMLog, type CronPayload } from "@chainlink/cre-sdk";
import {
  type BaseWorkflowConfig,
  buildEnvelope,
  parseProfileWorkflowConfig,
} from "./types";
import {
  parseHttpInput,
  registerBaseTriggers,
  resolveCronTimestampSeconds,
  safeJson,
} from "./runtime";

const PROFILE_ID = "QUANT_BASIS_LIQUIDITY_V1" as const;

const onHttpTrigger = (runtime: Runtime<BaseWorkflowConfig>, payload: unknown): string => {
  const body = parseHttpInput(payload);
  const executionId =
    typeof body.executionId === "string" && body.executionId.length > 0
      ? body.executionId
      : `${PROFILE_ID}-${Date.now()}`;

  runtime.log(`[${PROFILE_ID}] HTTP trigger received`);

  return safeJson(
    buildEnvelope({
      executionId,
      strategyId: PROFILE_ID,
      trigger: "http",
      decision: "NO_ACTION",
      reason: "Slide 0 skeleton: trigger wiring + structured envelope only",
      metadata: {
        hasRequestBody: Object.keys(body).length > 0,
      },
    })
  );
};

const onEvmLogTrigger = (_runtime: Runtime<BaseWorkflowConfig>, _payload: EVMLog): string =>
  safeJson(
    buildEnvelope({
      executionId: `${PROFILE_ID}-evm-${Date.now()}`,
      strategyId: PROFILE_ID,
      trigger: "evm_log",
      decision: "NO_ACTION",
      reason: "Slide 0 skeleton: EVM log trigger registered",
    })
  );

const onCronTrigger = (_runtime: Runtime<BaseWorkflowConfig>, payload: CronPayload): string =>
  safeJson(
    buildEnvelope({
      executionId: `${PROFILE_ID}-cron-${Date.now()}`,
      strategyId: PROFILE_ID,
      trigger: "cron",
      decision: "NO_ACTION",
      reason: "Slide 0 skeleton: cron watchdog registration",
      metadata: {
        triggerTimestamp: resolveCronTimestampSeconds(payload),
      },
    })
  );

const initWorkflow = (rawConfig: BaseWorkflowConfig) => {
  const parsed = parseProfileWorkflowConfig(rawConfig, PROFILE_ID);

  return registerBaseTriggers(parsed, {
    onHttp: onHttpTrigger,
    onEvmLog: onEvmLogTrigger,
    onCron: onCronTrigger,
  });
};

export async function main() {
  const runner = await Runner.newRunner<BaseWorkflowConfig>();
  await runner.run(initWorkflow);
}

main();
