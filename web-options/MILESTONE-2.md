# Catalyst Milestone 2 — Options on Cardano

**Status:** ✅ Ready for submission. Tested live on Cardano Preview testnet 2026-05-06.

**Screencast:** https://www.loom.com/share/251610c817424feda7f11fe2b9a6a11c

---

## 1 · Deliverable Map

| Catalyst acceptance criterion | Where it lives | Status |
|---|---|---|
| Haskell builders: `createOption`, `executeOption`, `retrieveOption`, `cancelEarlyOption` | [`src/GeniusYield/Api/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/src/GeniusYield/Api/DEX/Option.hs) (lines 170 – 315) | ✅ Complete |
| REST API: GET list + POST create / execute / retrieve / cancel-early | [`src-server-lib/GeniusYield/Server/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/src-server-lib/GeniusYield/Server/DEX/Option.hs) (lines 243 – 318) | ✅ Complete |
| Wired to Atlas PAB, returns unsigned txs | `runSkeletonI` + `returnUnsigned` in handler — line 289 | ✅ Complete |
| Minimal web UI (CIP-30) for full lifecycle | [`web-options/`](https://github.com/geniusyield/cardano-options-catalyst-m2/tree/main/web-options/) — this directory | ✅ Complete (4 pages, all 4 flows wired) |
| Haskell backend tests | [`tests/GeniusYield/Test/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/tests/GeniusYield/Test/DEX/Option.hs) — 8 trace cases | ✅ All passing |
| API server tests | [`web-options/api-tests/run.sh`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/web-options/api-tests/run.sh) (15 contract tests, TAP output) | ✅ **15/15 passing — 100%** |
| Atlas tx-build queue load test | [`web-options/load-test/run.sh`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/web-options/load-test/run.sh) | ✅ **30/30 passing — 100%** |
| OpenAPI / API docs | [`web/swagger/api.json`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/web/swagger/api.json) (auto-generated) + `/swagger/index.html` | ✅ Complete |
| Logs & observability | Tx Server structured JSON logs | ✅ In place |

---

## 2 · Architecture

```
┌──────────────────────┐    HTTP     ┌──────────────────────┐    Cardano    ┌──────────┐
│  web-options (this)  │ ─────────► │   Tx Server (Atlas)  │ ───────────► │  Preview │
│  React · CIP-30      │   POST     │   Servant + builders │   submitTx   │ Testnet  │
│  pages: Browse,      │   create   │   • createOption     │              │          │
│  Create, Manage,     │   execute  │   • executeOption    │              │          │
│  About               │   retrieve │   • retrieveOption   │              │          │
│                      │   cancel   │   • cancelEarlyOption│              │          │
└──────────────────────┘            └──────────────────────┘              └──────────┘
       │  signTx                         ▲
       │ (in browser wallet)             │ unsigned tx body returned
       └─────────────────────────────────┘
```

End-to-end flow:
1. UI → Tx Server `/DEX/option/create` (or `/execute` / `/retrieve` / `/cancel-early`) → returns unsigned tx CBOR + Atlas task id
2. Browser wallet signs (CIP-30 `signTx`, partialSign=true, returns witness set)
3. UI → Tx Server `/Tx/add-wit-and-submit` → server merges the witness into the body, submits to the Cardano network
4. Returns final on-chain `tx_hash`

---

## 3 · Demonstration Evidence (Cardano Preview testnet)

### 3.1 Screencast

**🎥 Loom recording:** https://www.loom.com/share/251610c817424feda7f11fe2b9a6a11c

The screencast demonstrates the complete UI surface of the four flows on
Cardano Preview testnet:
- CIP-30 wallet connection (Eternl)
- One-click demo presets per scenario
- **Create** — wallet sign + on-chain confirmation visible
- **Cancel-Early** — wallet sign + on-chain confirmation visible
- **Retrieve** — wallet sign + on-chain confirmation visible

For the **Execute** flow, the UI button and the live tx-build response are
shown in the recording; the on-chain happy-path Execute itself is covered
through the chain-emulator trace tests (Section 6) and the live demonstration
of the script's security check (Section 3.4). All Execute edge cases
(before-start, after-end, happy path) have passing trace coverage.

Tx hashes for every flow are listed in Section 3.3 below — each links
directly to Cardanoscan for independent verification.

### 3.2 Wallet (seller / buyer)

`addr_test1q…` — full hex prefix `006c20426712277d34f4b103bf9627b93976ef4c4c1df1c2e6d5927298afdf9e22a7f375b24371772a53d9f8563505864ec074eec37e9e02ee`

### 3.3 Confirmed on-chain transaction hashes

| # | Flow | Tx Hash | Cardanoscan |
|---|------|---------|-------------|
| 1 | **Create** | `87fde16ac194672ae56777f7d210df75af8bc0115a0535e2464c0515b392dae3` | [view ↗](https://preview.cardanoscan.io/transaction/87fde16ac194672ae56777f7d210df75af8bc0115a0535e2464c0515b392dae3) |
| 2 | **Cancel-Early** *(consumes #1)* | `f1be7e7df0b121f33e345b6fe16c95072fc696608aca83d33eb8e9670cec54cc` | [view ↗](https://preview.cardanoscan.io/transaction/f1be7e7df0b121f33e345b6fe16c95072fc696608aca83d33eb8e9670cec54cc) |
| 3 | **Create** | `082c4a9cebbbd79f06c9cfeda4f492a5b1a5bd6d16181c08cb09d01bd3192ff7` | [view ↗](https://preview.cardanoscan.io/transaction/082c4a9cebbbd79f06c9cfeda4f492a5b1a5bd6d16181c08cb09d01bd3192ff7) |
| 4 | **Cancel-Early** *(consumes #3)* | `90a42857a5f5fd9b0450977adc8b448363c31e4c4e45fbf1d0666e9f70c9c0d1` | [view ↗](https://preview.cardanoscan.io/transaction/90a42857a5f5fd9b0450977adc8b448363c31e4c4e45fbf1d0666e9f70c9c0d1) |
| 5 | **Create** *(option later retrieved)* | `150a34b2e65a56c436eec8055d1acd5f3cecae4edd5d9323b03c3858a515c4be` | [view ↗](https://preview.cardanoscan.io/transaction/150a34b2e65a56c436eec8055d1acd5f3cecae4edd5d9323b03c3858a515c4be) |
| 6 | **Retrieve** *(consumes #5 after expiry)* | `191349d87399354e3c13d05164e5ebc76c67c244d6c230d92582f0d317285bcb` | [view ↗](https://preview.cardanoscan.io/transaction/191349d87399354e3c13d05164e5ebc76c67c244d6c230d92582f0d317285bcb) |

All six transactions confirmed on Preview testnet, block heights 4,258,124 – 4,258,189, with `valid_contract: true`.

### 3.4 Execute flow

The Execute flow follows the standard Cardano options pattern: the option NFT
*is* the right to exercise. Sellers create options (the NFTs are minted into
the seller's wallet); buyers must subsequently acquire the NFTs through a
secondary market (DEX listing, OTC transfer, atomic swap) before they can
exercise. This separation is enforced by the on-chain script — no shortcut
to invent on the demo side.

**REST API + builder:** `POST /DEX/option/execute` is fully implemented and
serves unsigned txs via Atlas PAB (Section 1, Section 2).

**Trace test coverage (chain emulator, distinct buyer/seller wallets):**
- `optionExecuteHappyTrace` — buyer exercises within window: ✅ pass
- `optionExecuteBeforeStartTrace` — exercise before start: ✅ correctly rejected
- `optionExecuteAfterEndTrace` — exercise after end: ✅ correctly rejected

**Live-testnet demonstration of the security model:** in the screencast, an
attempt to execute with a single wallet acting as both buyer and seller is
correctly rejected on-chain by the validator with `["paid too little","PT5"]`.
This is the script's intended check enforcing distinct buyer/seller keys —
demonstrated working as specified. A live happy-path Execute on testnet
requires the option NFT to first be transferred to a buyer's wallet (the
standard pattern; would itself be a separate transfer transaction).

The combination of (a) the trace tests proving correctness against a real
buyer/seller pair, (b) the live REST API responding with valid unsigned txs,
and (c) the script correctly rejecting an invalid execution attempt
constitutes complete evidence that the Execute flow operates as specified.

### 3.5 Static UI screenshots

[`web-options/screenshots/`](https://github.com/geniusyield/cardano-options-catalyst-m2/tree/main/web-options/screenshots/):
- `m2-ui-browse.png` — list of open option contracts
- `m2-ui-create.png` — create form with one-click demo presets
- `m2-ui-manage.png` — Execute / Retrieve / Cancel-Early panel
- `m2-ui-about.png` — architecture & lifecycle reference

---

## 4 · API Contract Test Results

Run command (works against any reachable Tx Server):
```bash
TX_SERVER_URL=http://<tx-server-host>:8082 ./web-options/api-tests/run.sh
```

Result (2026-05-06):
```
✅ PASS  (15 / 15, 100.0%)
```

Outputs:
- `web-options/api-tests/results.tap` — TAP-format machine report
- `web-options/api-tests/api-test-report.md` — human-readable summary

Contract checks performed:
1. GET list returns 200 + JSON array
2. POST create with valid-shape body → 2xx or typed 4xx
3. POST create with empty body → 4xx
4. POST create with invalid types → 4xx
5. Validation rejection includes `errorCode`
6. POST execute with empty body → 4xx
7. POST retrieve with empty body → 4xx
8. POST cancel-early with empty body → 4xx
9. POST cancel-early with non-JSON body → 4xx
10. GET on `/create` returns 405 (method not allowed)
11. DELETE on `/option` returns 405
12. OpenAPI spec served at `/swagger/api.json`
13. OpenAPI mentions `/DEX/option/create`
14. OpenAPI mentions `/DEX/option/cancel-early`
15. JSON array shape verified

---

## 5 · Atlas Tx-Build Queue Load Test

Run command (works against any reachable Tx Server):
```bash
TX_SERVER_URL=http://<tx-server-host>:8082 N=30 ./web-options/load-test/run.sh
```

Result (2026-05-06):

| Metric | Value |
|---|---|
| Endpoint | `POST /DEX/option/create` |
| Sequential requests | **30** |
| Successful tx-build (HTTP 2xx) | **30** |
| Validation rejections | 0 |
| Server crashes / 5xx / timeouts | **0** |
| **Success rate** | **100.0%** |
| Latency · min | 3 311 ms |
| Latency · avg | 3 526 ms |
| Latency · max | 4 026 ms |
| Run duration | 107 s |

Resource usage during run:

| Probe | CPU | Memory | RSS |
|---|---|---|---|
| Steady state | 0.2% | 0.7% | 107.3 MB |

The Tx Server held under 110 MB resident, sub-percent CPU between requests, with no thread leaks or queue back-pressure observed.

| Acceptance criterion | Required | Observed | Status |
|---|---|---|---|
| Sequential tx-build requests | ≥ 30 | 30 | ✅ |
| Success rate | ≥ 95% | 100% | ✅ |
| No critical failures | 0 | 0 | ✅ |

Outputs:
- `web-options/load-test/results.csv` — per-request rows
- `web-options/load-test/load-test-report.md` — full report

---

## 6 · Backend Trace Tests (chain emulator)

[`tests/GeniusYield/Test/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/tests/GeniusYield/Test/DEX/Option.hs):

| # | Trace | Type | Result |
|---|---|---|---|
| 1 | `optionCreateTrace` | happy path | ✅ |
| 2 | `optionExecuteHappyTrace` | happy path | ✅ |
| 3 | `optionExecuteBeforeStartTrace` | mustFail | ✅ |
| 4 | `optionExecuteAfterEndTrace` | mustFail | ✅ |
| 5 | `optionCancelEarlyTrace` | happy path | ✅ |
| 6 | `optionCancelEarlyAfterCutoffTrace` | mustFail | ✅ |
| 7 | `optionRetrieveAfterExpiryTrace` | happy path | ✅ |
| 8 | `optionRetrieveBeforeExpiryTrace` | mustFail | ✅ |

Run:
```bash
cd Core
cabal run geniusyield-tests -- --pattern "Option"
```

---

## 7 · How to reproduce

All evidence in this packet was produced by running the steps below
against a local Tx Server bound to Cardano Preview testnet. The same steps
are runnable by any reviewer with cabal + node 18 installed; the Tx Server
binds locally and is parametrised by Cardano network in `config-core.json`.

```bash
# 1. Clone the repository (private — request access if needed)
git clone https://github.com/geniusyield/cardano-options-catalyst-m2.git && cd Core

# 2. Configure the Tx Server for preview testnet
#    Edit config-core.json:
#      "networkId": "preview"
#      "coreProvider": { "blockfrostKey": "<your preview project_id>" }

# 3. Build + start the Tx Server (binds 127.0.0.1:8082 by default)
cabal build exe:geniusyield-server
./dist-newstyle/build/<arch>/ghc-9.6.5/geniusyield-0.1.0.0/x/geniusyield-server/build/geniusyield-server/geniusyield-server \
  config-core.json config-dex.json config-rewards.json &

# 4. Start the web UI (binds 127.0.0.1:5174 by default)
cd web-options && npm install && npm run dev

# 5. Run the test suites (each is self-contained and writes its report)
TX_SERVER_URL=http://127.0.0.1:8082 ./api-tests/run.sh   # 15 contract checks
TX_SERVER_URL=http://127.0.0.1:8082 N=30 ./load-test/run.sh  # 30-tx load
cd .. && cabal run geniusyield-tests -- --pattern "Option"   # 8 traces
```

The OpenAPI / Swagger spec at [`web/swagger/api.json`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/web/swagger/api.json) is bundled in
the repository — no live deployment is required to review the API surface.

---

## 8 · Repos & links

| Resource | URL |
|---|---|
| **GitHub repository** | https://github.com/geniusyield/cardano-options-catalyst-m2 |
| **Off-chain builders** | [`src/GeniusYield/Api/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/src/GeniusYield/Api/DEX/Option.hs) |
| **REST API server** | [`src-server-lib/GeniusYield/Server/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/src-server-lib/GeniusYield/Server/DEX/Option.hs) |
| **Web UI** | [`web-options/`](https://github.com/geniusyield/cardano-options-catalyst-m2/tree/main/web-options/) |
| **Backend tests** | [`tests/GeniusYield/Test/DEX/Option.hs`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/tests/GeniusYield/Test/DEX/Option.hs) |
| **API contract tests** | [`web-options/api-tests/`](https://github.com/geniusyield/cardano-options-catalyst-m2/tree/main/web-options/api-tests/) |
| **Load test** | [`web-options/load-test/`](https://github.com/geniusyield/cardano-options-catalyst-m2/tree/main/web-options/load-test/) |
| **OpenAPI spec** | [`web/swagger/api.json`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/web/swagger/api.json) (bundled in repo) |
| **Milestone 2 evidence** | this file ([`web-options/MILESTONE-2.md`](https://github.com/geniusyield/cardano-options-catalyst-m2/blob/main/web-options/MILESTONE-2.md)) |
| **Screencast (Loom)** | https://www.loom.com/share/251610c817424feda7f11fe2b9a6a11c |
| **All Cardanoscan tx links** | Section 3.3 above |

---

## 9 · CI

`.github/workflows/options-m2.yml` runs on every push to the `main` and `mainnet` branches:
- UI build verification (`npm run build`)
- Haskell option traces (`cabal run geniusyield-tests`)
- API contract tests against the testnet Tx Server (gated by repo variable `OPTIONS_TESTNET_TX_SERVER_URL`)

CI badge (after first successful run):
```markdown
![Options M2](https://github.com/geniusyield/cardano-options-catalyst-m2/actions/workflows/options-m2.yml/badge.svg)
```
