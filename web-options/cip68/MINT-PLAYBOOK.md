# M3 CIP-68 demo mint playbook

End-to-end runbook for capturing the Catalyst Milestone 3 evidence:
two on-chain option series with CIP-68 metadata, plus wallet-rendering
proof in Lace, Eternl, and pool.pm.

## What you'll produce

1. Two confirmed Cardano Preview testnet transactions:
   - **M3-Call**: ADA→GENS @ 0.5, cancellable.
   - **M3-Put**: GENS→ADA @ 0.6, non-cancellable.
2. Screenshots of each wallet rendering the user NFT with the
   CIP-68 metadata (name, image, description).
3. A short screencast capturing the create flow + wallet rendering.

If you don't hold tGENS on preview, substitute any preview asset you
do hold. The CIP-68 demo proves *metadata rendering*, not economic
realism — the underlying assets are immaterial to evaluators.

## Pre-flight (one-time setup)

1. **Tx Server** running locally on `:8082`:
   ```
   cd Core
   export geniusyield_datadir="geniusyield-onchain/compiled"
   ./dist-newstyle/build/aarch64-osx/ghc-9.6.6/geniusyield-0.1.0.0/x/geniusyield-server/build/geniusyield-server/geniusyield-server config-core.json config-dex.json config-rewards.json
   ```
2. **web-options dev server** running on `:5174`:
   ```
   cd Core/web-options
   yarn dev
   ```
3. **Lace** wallet installed, connected to **Preview testnet**, funded
   with ≥10 tADA. Eternl as a backup signer.

## Recording flow (10 minutes)

### Take 1 — M3 Call series

1. Open `http://localhost:5174/create-cip68`.
2. Connect Lace (preview).
3. Click the **"M3 Call demo · ADA→GENS @ 0.5"** preset card. All
   fields populate from `CreateCIP68.tsx`'s preset.
4. Click **"Mint CIP-68 series"**. Lace pops up; sign.
5. After confirmation:
   - Copy the tx hash from the "CIP-68 option series minted" banner.
   - Copy the **reference NFT asset id** from the info banner above.
6. Open Lace's NFT tab → confirm the **user NFT** appears with the
   badge image + display name + description rendered from the CIP-68
   datum.

### Take 2 — M3 Put series

Repeat with the **"M3 Put demo · GENS→ADA @ 0.6"** preset. Capture the
tx hash and the second user NFT in the wallet.

### Take 3 — Cross-wallet verification

For each series, open the user NFT in:

- **Lace** (already done in Take 1/2).
- **Eternl** (connect on preview, look at NFTs tab).
- **pool.pm** — paste the user NFT asset id at
  `https://pool.pm/<policy>.<assetName>` (replace the label prefix
  `0x000de140` in the asset name with the actual ref-NFT body).

## What to capture in the screencast

For each series, ensure the recording shows:

- The Create-CIP68 form pre-filled by the preset.
- The wallet signing prompt.
- The "minted" confirmation with the ref-NFT asset id and address.
- The wallet's NFT view rendering the metadata.

Optional but recommended: open `https://preview.cardanoscan.io/transaction/<tx-hash>`
and show `valid_contract: true` plus the mint section listing the
three minted asset names (seller NFT, ref NFT with `0x000643b0`
prefix, user NFT with `0x000de140` prefix).

## Tx-hash table (fill in after the recording)

| Series   | Tx hash | Reference NFT asset | User NFT asset | Block height |
|----------|---------|---------------------|----------------|--------------|
| M3-Call  |         |                     |                |              |
| M3-Put   |         |                     |                |              |

## Acceptance-criteria mapping

| Criterion (M3 spec)                                                                 | Where evidenced                                |
|-------------------------------------------------------------------------------------|------------------------------------------------|
| Extend minting policy to produce CIP-68 compliant reference NFT per option series   | `createOptionWithCIP68` mints ref+user pair    |
| Wallet readability across major wallets                                             | Take 3 screenshots (Lace, Eternl, pool.pm)     |
| At least two distinct option series minted on testnet                               | M3-Call + M3-Put tx hashes in table above      |
| Inline datum carries name / image / description plus option-specific fields         | `metadataFromOptionParams` in `CIP68.hs`       |
| Reference NFT permanently locked (datum immutable)                                  | `cip68ReferenceValidator` AlwaysFails + trace  |
