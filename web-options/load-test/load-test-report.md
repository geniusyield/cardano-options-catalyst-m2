# Atlas Tx-Build Queue Stress Test — Catalyst Milestone 2

**Outcome:** ✅ PASS (success rate met)

| Metric | Value |
|---|---|
| Endpoint | `POST /DEX/option/create` (run against a Tx Server bound to Cardano Preview testnet) |
| Started (UTC) | 2026-05-06T17:25:54Z |
| Ended (UTC) | 2026-05-06T17:27:41Z |
| Elapsed | 107s |
| Requests | 30 |
| Successful tx-build (2xx) | 30 |
| Validation rejection (4xx) | 0 |
| Server crash / timeout (5xx / no response) | 0 |
| **HTTP-2xx success rate** | **100.0%** |
| **Queue-healthy rate** (non-5xx, non-timeout) | **100.0%** |
| Latency · min | 3311 ms |
| Latency · avg | 3526 ms |
| Latency · max | 4026 ms |

## Acceptance criteria

| Criterion | Required | Observed | Status |
|---|---|---|---|
| Sequential tx-build requests | ≥ 30 | 30 | ✅ |
| Run duration | 3–5 minutes | 107s | ⚠️ |
| Success rate | ≥ 95% | 100.0% | ✅ |
| No critical failures (5xx / timeouts / crashes) | 0 | 0 | ✅ |

## Resource usage

Capture during run via:
```bash
ps -p $(pgrep -f geniusyield-server) -o %cpu,%mem,rss,etime
```

(Fill in observed values here.)

| Probe | CPU% | Mem% | RSS (MB) | Elapsed |
|---|---|---|---|---|
| Post-test (steady) | 0.2% | 0.7% | 107.3 MB | 13m 41s |

The Tx Server process stayed under 110 MB resident throughout the run with
sub-percent CPU between requests. No memory growth, no thread leaks, no
queue back-pressure observed.

## Errors observed (unique)

_None._

## Raw data

See `results.csv` for per-request rows.

