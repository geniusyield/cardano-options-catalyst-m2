# GeniusYield Options · Testnet UI

Standalone web UI for the GeniusYield Options on Cardano (Catalyst Milestone 2).

This app is **completely separate** from the public GeniusYield app. It is an
audit-friendly demo of the four option flows: **create → execute → retrieve →
cancel-early**.

```
web-options/
├── src/                  React + TypeScript source
│   ├── pages/            Browse · Create · Manage · About
│   ├── lib/              api.ts (REST client) · wallet.ts (CIP-30)
│   └── components/       AppShell with wallet connect
├── api-tests/            REST API contract tests (TAP output)
│   └── run.sh
├── load-test/            Atlas tx-build queue stress test
│   ├── run.sh
│   └── payload.json
└── MILESTONE-2.md        Catalyst submission packet
```

## Quick start

```bash
npm install
npm run dev      # http://localhost:5174
```

By default the UI proxies `/api` → `http://localhost:8082` (the Tx Server).
Override with `OPTIONS_API_URL=https://… npm run dev` or set
`VITE_OPTIONS_API_URL` for production builds.

## Test suites

```bash
# REST API contract tests (10 checks)
TX_SERVER_URL=https://testnet-tx ./api-tests/run.sh

# Atlas queue stress test (≥30 sequential builds)
TX_SERVER_URL=https://testnet-tx ./load-test/run.sh
```

Both produce machine-readable output (`results.tap`, `results.csv`) and a
human-readable Markdown report.

See [MILESTONE-2.md](MILESTONE-2.md) for the full Catalyst deliverable map.
