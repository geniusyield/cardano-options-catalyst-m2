// CIP-30 wallet bridge.
// Each Cardano browser wallet exposes itself on `window.cardano.<name>` with
// `enable()` returning an API object with the standard CIP-30 methods.

declare global {
  interface Window {
    cardano?: Record<string, CardanoWalletStub>;
  }
}

interface CardanoWalletStub {
  name: string;
  icon?: string;
  enable: () => Promise<CardanoWalletApi>;
  isEnabled: () => Promise<boolean>;
}

export interface CardanoWalletApi {
  getUsedAddresses: () => Promise<string[]>;
  getUnusedAddresses: () => Promise<string[]>;
  getChangeAddress: () => Promise<string>;
  getCollateral?: () => Promise<string[] | null>;
  getRewardAddresses?: () => Promise<string[]>;
  getNetworkId?: () => Promise<number>;
  signTx: (txCbor: string, partialSign?: boolean) => Promise<string>;
  submitTx: (txCbor: string) => Promise<string>;
}

export interface ConnectedWallet {
  name: string;
  api: CardanoWalletApi;
  changeAddress: string;
  usedAddresses: string[];
  collateral: string | null;
  networkId: number;
}

const PREFERRED = ['nami', 'eternl', 'flint', 'lace', 'gerowallet', 'typhon', 'yoroi'];

export function listAvailableWallets(): { id: string; name: string }[] {
  if (typeof window === 'undefined' || !window.cardano) return [];
  const found: { id: string; name: string }[] = [];
  for (const id of Object.keys(window.cardano)) {
    const w = window.cardano[id];
    if (w && typeof w.enable === 'function' && typeof w.name === 'string') {
      found.push({ id, name: w.name });
    }
  }
  // Bring preferred ones to the top
  return found.sort((a, b) => {
    const ai = PREFERRED.indexOf(a.id);
    const bi = PREFERRED.indexOf(b.id);
    if (ai === -1 && bi === -1) return a.name.localeCompare(b.name);
    if (ai === -1) return 1;
    if (bi === -1) return -1;
    return ai - bi;
  });
}

export async function connectWallet(id: string): Promise<ConnectedWallet> {
  if (!window.cardano || !window.cardano[id]) {
    throw new Error(`Wallet "${id}" is not available in this browser.`);
  }
  const stub = window.cardano[id];
  const api = await stub.enable();

  const [usedAddresses, changeAddress, networkId, collateralRaw] = await Promise.all([
    api.getUsedAddresses(),
    api.getChangeAddress(),
    api.getNetworkId ? api.getNetworkId() : Promise.resolve(0),
    api.getCollateral ? api.getCollateral().catch(() => null) : Promise.resolve(null),
  ]);

  const collateral =
    collateralRaw && collateralRaw.length > 0 ? collateralRaw[0] : null;

  return {
    name: stub.name,
    api,
    changeAddress,
    usedAddresses,
    collateral,
    networkId,
  };
}

export function shortAddr(addr: string): string {
  if (!addr) return '';
  if (addr.length < 16) return addr;
  return `${addr.slice(0, 8)}…${addr.slice(-6)}`;
}

/**
 * Sign + submit flow.
 *
 *  1. Wallet signs the original unsigned tx (partialSign=true) and returns just
 *     the witness set CBOR.
 *  2. We POST { originalUnsignedTx, walletWitness } to the Tx Server's
 *     `/Tx/add-wit-and-submit` endpoint, which merges the witness into the body
 *     and submits to the network. This avoids bundling cardano-serialization-lib
 *     (~2 MB wasm) just to combine two CBOR blobs.
 *  3. The server returns `tx_hash`.
 */
const TX_API_BASE = (import.meta.env.VITE_OPTIONS_API_URL as string) || '/api';

let inFlightCount = 0;
// Cache of recently-signed txs so a duplicate invocation of signAndSubmit with
// the *same* tx body returns the original hash instead of re-popping the
// wallet. Cleared 30 s after success.
const recentResults = new Map<string, Promise<string>>();

export async function signAndSubmit(
  wallet: ConnectedWallet,
  txCborHex: string
): Promise<string> {
  // Idempotency: if we've already started signing this exact tx, return the
  // existing in-flight or resolved Promise instead of starting a new one.
  const cached = recentResults.get(txCborHex);
  if (cached) {
    console.warn('[wallet] signAndSubmit DEDUPED — same tx body already being processed');
    return cached;
  }

  inFlightCount += 1;
  if (inFlightCount > 1) {
    console.warn(
      `[wallet] signAndSubmit invoked while ${inFlightCount - 1} call(s) already in flight — blocked`
    );
    inFlightCount -= 1;
    throw new Error('A signature request is already in progress. Please wait for it to finish.');
  }

  const promise = (async (): Promise<string> => {
    console.log('[wallet] signAndSubmit START tx-prefix=' + txCborHex.slice(0, 16));
    const walletWitness = await wallet.api.signTx(txCborHex, true);
    console.log('[wallet] signTx returned witness-len=' + walletWitness.length);

    const res = await fetch(`${TX_API_BASE}/Tx/add-wit-and-submit`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        originalUnsignedTx: txCborHex,
        walletWitness,
      }),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      if (
        text.includes('All inputs are spent') ||
        text.includes('BadInputs') ||
        text.includes('inputs already in mempool')
      ) {
        throw new Error(
          "Your previous transaction is still being confirmed on-chain. Please wait ~60 seconds and try again — the wallet currently sees the same UTxOs as 'in flight'."
        );
      }
      throw new Error(`add-wit-and-submit: ${res.status} ${res.statusText} — ${text.slice(0, 240)}`);
    }

    const json = (await res.json()) as { tx_hash?: string; txHash?: string; tx_id?: string };
    const txHash = json.tx_hash ?? json.txHash ?? json.tx_id;
    if (!txHash) throw new Error('Server did not return tx_hash');
    console.log('[wallet] signAndSubmit OK tx-hash=' + txHash);
    return txHash;
  })();

  // Cache the promise (resolved or pending) under the tx body so a duplicate
  // call returns the same result rather than re-prompting the wallet.
  recentResults.set(txCborHex, promise);
  // On settle: decrement in-flight counter; on success, keep the cache for
  // 30 s so any straggling re-invocation gets the same hash.
  promise.finally(() => {
    inFlightCount -= 1;
    setTimeout(() => recentResults.delete(txCborHex), 30_000);
  });

  return promise;
}
