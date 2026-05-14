# GeniusYield — Cardano Options (Catalyst M2)

This repository contains the **Milestone 2 deliverables** for the Project
Catalyst proposal **"Cardano Options on Smart Vaults"** by GeniusYield. It is
a curated public snapshot extracted from a larger private development
monorepo so that the on-chain validator, off-chain builders, REST API
server, web UI, and test artefacts referenced in the milestone evidence
document can be reviewed openly.

## What's here

| Layer | Path | What it does |
|---|---|---|
| **Plutus on-chain validator** | [`src-plutustx/GeniusYield/OnChain/DEX/Option.hs`](src-plutustx/GeniusYield/OnChain/DEX/Option.hs) | PlutusTx validator enforcing the option lifecycle (create / execute / retrieve / cancel-early) |
| Plutus compiled blueprint | [`src-plutustx/GeniusYield/OnChain/DEX/Option/Compiled.hs`](src-plutustx/GeniusYield/OnChain/DEX/Option/Compiled.hs) | Loads the compiled validator into Haskell as `GYScript` |
| **Aiken reference port** | [`aiken/options/validators/option.ak`](aiken/options/validators/option.ak) | Independent Aiken implementation of the same logic (audit cross-check) |
| **Haskell off-chain builders** | [`src/GeniusYield/Api/DEX/Option.hs`](src/GeniusYield/Api/DEX/Option.hs) | `createOption` · `executeOption` · `retrieveOption` · `cancelEarlyOption` |
| Script loader | [`src/GeniusYield/Scripts/DEX/Option.hs`](src/GeniusYield/Scripts/DEX/Option.hs) | Loads the validator + parameter inference |
| **REST API server** | [`src-server-lib/GeniusYield/Server/DEX/Option.hs`](src-server-lib/GeniusYield/Server/DEX/Option.hs) | Servant routes mounted at `/options/*` |
| **Backend trace tests (8 cases)** | [`tests/GeniusYield/Test/DEX/Option.hs`](tests/GeniusYield/Test/DEX/Option.hs) | Atlas trace tests covering happy paths + failure modes |
| **Web UI** | [`web-options/`](web-options/) | React + Vite frontend |
| Web UI · Browse | [`web-options/src/pages/Browse.tsx`](web-options/src/pages/Browse.tsx) | Open options market |
| Web UI · Create | [`web-options/src/pages/Create.tsx`](web-options/src/pages/Create.tsx) | Mint a new option |
| Web UI · Manage | [`web-options/src/pages/Manage.tsx`](web-options/src/pages/Manage.tsx) | Execute / Retrieve / Cancel-early flows |
| Web UI · About | [`web-options/src/pages/About.tsx`](web-options/src/pages/About.tsx) | About / docs page |
| API contract tests | [`web-options/api-tests/`](web-options/api-tests/) | TAP-format integration tests against the live server |
| Atlas queue load test | [`web-options/load-test/`](web-options/load-test/) | Concurrency / throughput benchmark |
| **OpenAPI spec** | [`web/swagger/api.json`](web/swagger/api.json) | Full Tx Server OpenAPI doc — search `option-` for the milestone endpoints |
| Milestone evidence | [`web-options/MILESTONE-2.md`](web-options/MILESTONE-2.md) | Section-by-section evidence document submitted to Catalyst |
| **CI workflow** | [`.github/workflows/options-m2.yml`](.github/workflows/options-m2.yml) | Builds + checks Haskell, Aiken, and the web UI on every push |

## What's NOT here, and why

This repository is intentionally minimal. The upstream private monorepo
(`geniusyield/Core`) contains thousands of additional files supporting
the broader GeniusYield DEX, Smart Vaults, staking, oracle integration,
and infrastructure — none of which are part of the M2 deliverable and
all of which include production secrets, signing keys, and PII that
cannot be open-sourced safely.

**Concretely, the published modules reference upstream-only types like
`GeniusYield.Imports`, `GeniusYield.TxBuilder`, `GeniusYield.OnChain.AnyMint`,
and the Atlas framework. Reviewers wishing to compile end-to-end need
access to the upstream repository.** The CI workflow in this repo runs
parsing-only checks for the Haskell modules; Aiken (`aiken/options/`)
and the web UI (`web-options/`) build standalone.

## Audit cross-reference

The on-chain validator has two independent implementations:

- **PlutusTx** at `src-plutustx/GeniusYield/OnChain/DEX/Option.hs` — the
  one currently deployed on mainnet.
- **Aiken** at `aiken/options/validators/option.ak` — a clean-room
  reference port that verifies the same lifecycle invariants. The two
  implementations are independent codebases sharing only the spec.

Both must reject the same invalid traces and accept the same valid ones.
The trace tests in `tests/GeniusYield/Test/DEX/Option.hs` exercise the
deployed validator against eight scenarios; the Aiken `aiken check`
target in `aiken/options/` exercises the reference port against the
same shapes.

## Catalyst evidence

See [`web-options/MILESTONE-2.md`](web-options/MILESTONE-2.md) for the
formal milestone-completion document, including the screencast link,
mainnet tx hashes, and a section-by-section evidence checklist.

## License

[Apache License 2.0](LICENSE). Code released as part of the Catalyst
Cardano Open Source program.

## Project links

- Project Catalyst proposal: https://projectcatalyst.io
- GeniusYield: https://geniusyield.co
- Cardano: https://cardano.org

## Disclaimer

This snapshot is provided for **review purposes only**. The mainnet
deployment uses the upstream private build pipeline; do not attempt to
re-derive operational secrets, hot wallets, or contract upgrade keys
from the code published here.
