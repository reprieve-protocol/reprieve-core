# CRE Workflow Development Guide

This document contains best practices and lessons learned from implementing CRE workflows for the tap.fun x Chainlink project.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Project Structure](#project-structure)
3. [Common Pitfalls](#common-pitfalls)
4. [Best Practices](#best-practices)
5. [Testing Strategy](#testing-strategy)
6. [Workflow Template](#workflow-template)
7. [Reference](#reference)

---

## Quick Start

### Running Tests

```bash
# Smart contract tests
cd /Users/sniperman/code/tapfun-chainlink-sc
forge test --summary

# CRE unit tests
cd /Users/sniperman/code/tapfun-chainlink-sc/cre
bun test

# TypeScript compilation
bun run build

# Workflow simulation
cre workflow simulate workflow-name --target local-simulation
```

---

## Project Structure

### ⚠️ CRITICAL: File Co-location Requirement

The CRE compiler **CANNOT** resolve `../` parent directory imports. All files must be co-located within the workflow directory.

```
cre/
├── workflow-name/          # Workflow directory
│   ├── main.ts               # Entry point (REQUIRED)
│   ├── workflow.yaml         # Workflow config (REQUIRED)
│   ├── config.json           # Runtime config (REQUIRED)
│   ├── types.ts              # Shared types (local copy)
│   ├── config.ts             # Workflow config (local copy)
│   └── lib/                  # Utilities (local copies)
│       ├── api.ts
│       ├── hash.ts
│       └── ethereum.ts
├── settlement/               # Next workflow
│   ├── main.ts
│   ├── workflow.yaml
│   ├── config.json
│   └── lib/                  # Copy needed utilities locally
├── src/                      # Source templates (DO NOT IMPORT FROM HERE)
│   └── lib/                  # Template implementations
├── package.json
├── tsconfig.json
└── project.yaml
```

### Creating a New Workflow

1. **Copy the template workflow:**
```bash
cd /Users/sniperman/code/tapfun-chainlink-sc/cre
cp -r workflow-template my-new-workflow
```

2. **Update workflow.yaml:**
```yaml
local-simulation:
  user-workflow:
    workflow-name: "tapfun-my-workflow"
  workflow-artifacts:
    workflow-path: "./main.ts"
    config-path: "./config.json"
    secrets-path: "../secrets.yaml"
```

3. **Update config.json** with contract addresses

4. **Copy needed utilities:**
```bash
cp workflow-name/lib/api.ts my-new-workflow/lib/
cp workflow-name/lib/hash.ts my-new-workflow/lib/
# etc.
```

---

## Common Pitfalls

### ❌ Pitfall 1: Dynamic Imports

**WRONG - Causes WASM crash:**
```typescript
const { keccak256, toHex } = await import("viem");
```

**CORRECT - Static import at top:**
```typescript
import { keccak256, toHex } from "viem";
```

### ❌ Pitfall 2: Parent Directory Imports

**WRONG - CRE compiler cannot resolve:**
```typescript
import { something } from "../types";
import { helper } from "../lib/api";
```

**CORRECT - Local copy in workflow directory:**
```typescript
import { something } from "./types";
import { helper } from "./lib/api";
```

### ❌ Pitfall 3: Complex Config Schema

**WRONG - Can cause issues:**
```typescript
export async function main() {
  const runner = await Runner.newRunner<Config>({ configSchema });
  await runner.run(initWorkflow);
}
```

**CORRECT - Simpler approach:**
```typescript
export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
```

### ❌ Pitfall 4: Using Node.js APIs

**NOT SUPPORTED in WASM:**
- `fs` module
- `path` module
- `process.env` (use `runtime.getSecret()` instead)
- `console.log` in handlers (use `runtime.log()`)

### ❌ Pitfall 5: Incorrect Cron Pattern

**WRONG:**
```typescript
// 6-field expression may not work as expected
schedule: "0 */15 * * * *"
```

**CORRECT - 5-field expression:**
```typescript
schedule: "*/15 * * * *"  // Every 15 minutes
```

---

## Best Practices

### ✅ DO: Use Static Imports Only

```typescript
// At the top of the file
import { cre, type Runtime, Runner, type CronPayload } from "@chainlink/cre-sdk";
import { keccak256, toHex } from "viem";
import { configSchema, type Config } from "./types";
```

### ✅ DO: Use Correct SDK Import Pattern

```typescript
import {
  CronCapability,
  handler,
  type Runtime,
  type CronPayload,
  Runner,
} from "@chainlink/cre-sdk";
```

### ✅ DO: Use Runtime for Logging

```typescript
const onCronTrigger = async (runtime: Runtime<Config>, payload: CronPayload) => {
  runtime.log("This will appear in CRE logs");
  // NOT console.log - use runtime.log
};
```

### ✅ DO: Extract Timestamp from Payload

```typescript
const onCronTrigger = async (runtime: Runtime<Config>, payload: CronPayload) => {
  let triggerTimestamp = Math.floor(Date.now() / 1000);
  if (payload.scheduledExecutionTime?.seconds) {
    triggerTimestamp = Number(payload.scheduledExecutionTime.seconds);
  }
  // Use triggerTimestamp...
};
```

### ✅ DO: Initialize Workflow Correctly

```typescript
const initWorkflow = (config: Config) => {
  console.log("Initializing workflow"); // OK here, before WASM
  
  const cronTrigger = new CronCapability().trigger({
    schedule: "*/15 * * * *",
  });
  
  return [handler(cronTrigger, onCronTrigger)];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}

main();
```

### ✅ DO: Handle Async Operations Properly

```typescript
const onCronTrigger = async (runtime: Runtime<Config>, payload: CronPayload): Promise<string> => {
  try {
    const result = await fetchData();
    return `Success: ${result}`;
  } catch (error) {
    runtime.log(`Error: ${error}`);
    throw error; // Re-throw to fail the workflow
  }
};
```

---

## Testing Strategy

### Phase 1: Minimal Test (Isolate Issues)

Create a minimal test workflow to verify the basic setup:

```typescript
// test-minimal/main.ts
import {
  CronCapability,
  handler,
  type Runtime,
  type CronPayload,
  Runner,
} from "@chainlink/cre-sdk";

type Config = {};

const onCronTrigger = (runtime: Runtime<Config>, payload: CronPayload): string => {
  runtime.log("Cron trigger fired!");
  return "OK";
};

const initWorkflow = (config: Config) => {
  const cronTrigger = new CronCapability().trigger({
    schedule: "*/15 * * * *",
  });
  return [handler(cronTrigger, onCronTrigger)];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}

main();
```

### Phase 2: Add Imports Incrementally

Add one import at a time to identify problematic code:

```typescript
// Step 1: Add types
import { configSchema, type Config } from "../workflow-name/types";

// Step 2: Add config
import { priceIntegrityConfig } from "../workflow-name/config";

// Step 3: Add utilities one by one
import { createApiClient } from "../workflow-name/lib/api";
import { hashCandles } from "../workflow-name/lib/hash";
```

### Phase 3: Unit Tests (Bun)

```typescript
// lib/hash.test.ts
import { describe, it, expect } from "bun:test";
import { hashCandles } from "./hash";

describe("hashCandles", () => {
  it("should produce deterministic hash", () => {
    const candles = [{ timestamp: 1, open: "100", high: "110", low: "90", close: "105" }];
    const hash1 = hashCandles(candles);
    const hash2 = hashCandles(candles);
    expect(hash1).toBe(hash2);
  });
});
```

Run with: `bun test`

### Phase 4: CRE Simulation

```bash
cre workflow simulate workflow-name --target local-simulation
```

Use `-v` for verbose output, `-g` for engine logs:
```bash
cre workflow simulate workflow-name --target local-simulation -v -g
```

---

## Workflow Template

Copy this template to create new workflows:

```typescript
// workflow-template/main.ts
// ==========================================================================
// Workflow: [NAME] ([DESCRIPTION])
// ==========================================================================
//
// This workflow:
// 1. [Step 1]
// 2. [Step 2]
// 3. [Step 3]
//
// Trigger: [cron/http/evm]
// Contract: [ContractName.functionName(...)]

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
  // Extract timestamp
  let triggerTimestamp = Math.floor(Date.now() / 1000);
  if (payload.scheduledExecutionTime?.seconds) {
    triggerTimestamp = Number(payload.scheduledExecutionTime.seconds);
  }

  runtime.log("========================================");
  runtime.log("[Workflow Name] Started");
  runtime.log(`Trigger time: ${new Date(triggerTimestamp * 1000).toISOString()}`);
  runtime.log("========================================");

  try {
    // TODO: Implement workflow logic
    
    runtime.log("========================================");
    runtime.log("[Workflow Name] Completed");
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
  console.log("Initializing [Workflow Name]");

  const cronTrigger = new CronCapability().trigger({
    schedule: "*/15 * * * *", // Every 15 minutes
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
```

---

## Reference

### CRE SDK Exports

```typescript
// Core
import {
  cre,                    // Main SDK object
  Runner,                 // Workflow runner
  handler,                // Trigger handler factory
  type Runtime,           // Runtime interface
} from "@chainlink/cre-sdk";

// Triggers
import {
  CronCapability,
  type CronPayload,
  // HTTP triggers also available
} from "@chainlink/cre-sdk";
```

### Cron Schedule Formats

| Expression | Description |
|------------|-------------|
| `*/15 * * * *` | Every 15 minutes |
| `0 * * * *` | Every hour at :00 |
| `0 0 * * *` | Daily at midnight UTC |
| `TZ=America/New_York 0 9 * * 1-5` | Weekdays at 9 AM ET |

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `wasm trap: wasm unreachable` | Dynamic import or unsupported API | Use static imports only |
| `No workflow triggers found` | Incorrect handler setup | Check `initWorkflow` returns handlers array |
| `cannot read property 'X' of undefined` | Missing config property | Check `config.json` has all required fields |
| Import resolution error | Using `../` imports | Copy files locally to workflow directory |

### Documentation Links

- [CRE Docs](https://docs.chain.link/cre)
- [Cron Trigger TypeScript](https://docs.chain.link/cre/guides/workflow/using-triggers/cron-trigger-ts)
- [SDK Reference](https://docs.chain.link/cre/reference/sdk/triggers/overview-ts)

---

## Contact & Support

For issues with:
- **Smart Contracts**: Check Foundry tests in `/test`
- **CRE Workflows**: Check `workflow-name/` for working example
- **SDK Issues**: Refer to [Chainlink CRE Docs](https://docs.chain.link/cre)
