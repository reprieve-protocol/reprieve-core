// ==========================================================================
// Workflow Template
// ==========================================================================
//
// Copy this directory to create a new workflow:
//   cp -r workflow-template my-new-workflow
//
// Then update:
//   1. workflow.yaml - workflow name
//   2. config.json - your contract addresses
//   3. This file - your business logic
//   4. types.ts - add your types

import {
  CronCapability,
  handler,
  type Runtime,
  type CronPayload,
  Runner,
} from "@chainlink/cre-sdk";
import { type Config } from "./types";

// ========================================
// Trigger Handler
// ========================================

const onCronTrigger = async (
  runtime: Runtime<Config>,
  payload: CronPayload
): Promise<string> => {
  // Extract timestamp from payload
  let triggerTimestamp = Math.floor(Date.now() / 1000);
  if (payload.scheduledExecutionTime?.seconds) {
    triggerTimestamp = Number(payload.scheduledExecutionTime.seconds);
  }

  runtime.log("========================================");
  runtime.log("Workflow Started");
  runtime.log(`Trigger time: ${new Date(triggerTimestamp * 1000).toISOString()}`);
  runtime.log("========================================");

  try {
    // ========================================
    // Step 1: TODO - Implement your logic
    // ========================================
    
    runtime.log("Processing...");
    
    // Example: Fetch data
    // const data = await fetchSomeData(runtime);
    
    // Example: Compute something
    // const result = computeSomething(data);
    
    // Example: Submit on-chain
    // const txHash = await submitTransaction(runtime, result);
    
    runtime.log("========================================");
    runtime.log("Workflow Completed");
    runtime.log("========================================");

    return "Workflow completed successfully";
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    runtime.log(`ERROR: ${message}`);
    throw error;
  }
};

// ========================================
// Workflow Initialization
// ========================================

const initWorkflow = (config: Config) => {
  console.log("Initializing Workflow");

  // Configure cron trigger - fires every 15 minutes
  const cronTrigger = new CronCapability().trigger({
    schedule: "*/15 * * * *",
  });

  return [handler(cronTrigger, onCronTrigger)];
};

// ========================================
// Entry Point
// ========================================

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}

main();
