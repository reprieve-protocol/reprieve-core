# reprieve-quant-funding-oi-v1

Profile workflow for `QUANT_FUNDING_OI_V1`.

## Slide 0 status

- Trigger skeleton wired for HTTP + EVM log + cron.
- Emits structured execution envelope only.
- No risk model or on-chain rescue execution logic yet.

## Local checks

- `bun run build`
- `cre workflow simulate ./reprieve-quant-funding-oi-v1 --target=staging-settings`
