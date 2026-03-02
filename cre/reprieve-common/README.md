# reprieve-common

Shared Slide 0 CRE foundation for Reprieve profile workflows.

## Files

- `types.ts`
  - Base config types
  - Result envelope schema
  - Config parser + validation helpers
- `runtime.ts`
  - Trigger registration helpers (HTTP, EVM log, cron)
  - HTTP payload parser
  - Cron timestamp helper
  - Safe envelope serialization helper

## Important

The CRE compiler does not resolve parent imports in workflow builds.  
Each deployable workflow must keep local copies of shared files.

Use:

```bash
./scripts/cre/sync-common.sh
```

to copy `types.ts` and `runtime.ts` into profile workflow directories.
