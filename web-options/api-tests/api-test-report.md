# REST API Contract Tests — Catalyst Milestone 2

**Outcome:** ✅ PASS (15 / 15 passing — 100.0%)

| Run | Value |
|---|---|
| Endpoint base | Tx Server bound to Cardano Preview testnet (run via `TX_SERVER_URL=...` env var) |
| Started (UTC) | 2026-05-06T17:15:32Z |
| Ended (UTC) | 2026-05-06T17:15:33Z |
| Total tests | 15 |
| Passing | 15 |
| Failing | 0 |

## What is verified

| # | Check | Endpoint |
|---|---|---|
| 1 | GET list returns 200 + JSON array | GET `/DEX/option` |
| 2 | POST with valid body composes a tx (2xx) | POST `/DEX/option/create` |
| 3 | POST with empty body rejected (4xx) | all 4 POST routes |
| 4 | POST with malformed JSON rejected (4xx) | POST `/DEX/option/cancel-early` |
| 5 | Method routing — wrong verb returns 405 | GET on `/create`, DELETE on `/option` |
| 6 | OpenAPI doc served and mentions all endpoints | GET `/swagger/api.json` |

## Results

All checks passed.

## TAP output

See `results.tap` for a machine-readable report (compatible with most CI runners).

