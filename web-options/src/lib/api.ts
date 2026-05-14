// Thin client for the Tx Server's /DEX/option endpoints.
// All POST endpoints return an unsigned tx for the wallet to sign.

export interface OptionInfo {
  opiRef: string;
  opiOptionRef?: string;
  opiOptionToken: string;
  opiNFT?: string;
  opiStart: string;
  opiEnd: string;
  opiCancelCutoff: string;
  opiDepositAmt: number;
  opiDepositToken?: string;   // "lovelace" for ADA, otherwise "<policyId>.<assetName>"
  opiPaymentAmt: number;
  opiPaymentToken?: string;
  opiPrice: string;
  opiSellerKey?: string;
  opiValue?: Record<string, number>;
  // The server response carries more fields — kept loose here.
  [key: string]: unknown;
}

/** Render a token id (or "lovelace") as a friendly short label. */
export function formatToken(token: string | undefined): string {
  if (!token || token === 'lovelace' || token === '' || token === '.') return 'ADA';
  // Cardano token id format: "<policyId hex>.<assetName hex>"
  const [, assetHex] = token.split('.');
  if (assetHex && assetHex.length > 0 && assetHex.length <= 64) {
    try {
      // Decode hex asset name to UTF-8 if printable
      const bytes = assetHex.match(/.{1,2}/g)?.map((h) => parseInt(h, 16)) ?? [];
      const decoded = String.fromCharCode(...bytes);
      if (/^[\x20-\x7e]+$/.test(decoded)) return decoded;
    } catch { /* fall through */ }
    return assetHex.slice(0, 6) + '…';
  }
  return token.slice(0, 8) + '…';
}

/** Format an asset amount with unit-aware ADA conversion. */
export function formatAmount(amount: number, token: string | undefined): string {
  if (!token || token === 'lovelace' || token === '' || token === '.') {
    // Show ADA when amount is large enough; otherwise lovelace
    if (amount >= 1_000_000) {
      const ada = amount / 1_000_000;
      return `${ada.toLocaleString(undefined, { maximumFractionDigits: 6 })} ADA`;
    }
    return `${amount.toLocaleString()} lovelace`;
  }
  return `${amount.toLocaleString()} ${formatToken(token)}`;
}

export interface DexTxResponse {
  // Atlas / GeniusYield Tx Server uses these field names:
  tTx: string;                  // unsigned tx CBOR hex
  tScriptAddress?: string;      // script the tx outputs to
  tx_hash?: string;             // pre-computed tx id
  tx_fee?: number;
  tx_inputs?: unknown[];
  tx_outputs?: unknown[];
  tx_mints?: unknown[];
  // Loose — extra fields tolerated
  [key: string]: unknown;
}

/** Extract the unsigned tx CBOR from a Tx Server response, accepting common
 *  field aliases so we tolerate Atlas version drift. */
export function extractTxCbor(res: DexTxResponse): string {
  const candidate =
    res.tTx ??
    (res as any).txBodyHex ??
    (res as any).tx ??
    (res as any).txCborHex;
  if (typeof candidate !== 'string' || candidate.length === 0) {
    throw new Error('Server response has no unsigned tx body field (tTx).');
  }
  return candidate;
}

const BASE = (import.meta.env.VITE_OPTIONS_API_URL as string) || '/api';

async function postJson<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`${res.status} ${res.statusText} — ${text.slice(0, 240)}`);
  }
  return (await res.json()) as T;
}

async function getJson<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`${res.status} ${res.statusText} — ${text.slice(0, 240)}`);
  }
  return (await res.json()) as T;
}

export interface CreateCIP68Params {
  usedAddrs: string[];
  change: string;
  collateral?: string;
  start: string;
  end: string;
  cancelCutoff: string;
  depositSymbol: string;
  depositToken: string;
  paymentSymbol: string;
  paymentToken: string;
  price: number | string;
  amount: number;
  optionType: 'call' | 'put';
  cancellable: boolean;
  displayName: string;
  imageUri: string;
  description: string;
  feeCfgRef: string;
}

export interface DexTxResponseCreateCIP68 extends DexTxResponse {
  cip68ReferenceAddress: string;
  cip68ReferenceAsset: string;
}

export const api = {
  list: () => getJson<OptionInfo[]>('/DEX/option'),

  create: (params: {
    usedAddrs: string[];
    change: string;
    collateral?: string;
    start: string;
    end: string;
    cancelCutoff: string;
    depositSymbol: string;
    depositToken: string;
    paymentSymbol: string;
    paymentToken: string;
    price: number | string;
    amount: number;
  }) => postJson<DexTxResponse>('/DEX/option/create', params),

  createCIP68: (params: CreateCIP68Params) =>
    postJson<DexTxResponseCreateCIP68>('/DEX/option/create-cip68', params),

  execute: (params: {
    usedAddrs: string[];
    change: string;
    collateral?: string;
    ref: string;
    amount: number;
  }) => postJson<DexTxResponse>('/DEX/option/execute', params),

  retrieve: (params: {
    usedAddrs: string[];
    change: string;
    collateral?: string;
    ref: string;
  }) => postJson<DexTxResponse>('/DEX/option/retrieve', params),

  cancelEarly: (params: {
    usedAddrs: string[];
    change: string;
    collateral?: string;
    ref: string;
  }) => postJson<DexTxResponse>('/DEX/option/cancel-early', params),
};

// Lifecycle classification from option timestamps (ms or ISO).
export type Lifecycle = 'Not started' | 'Active' | 'Expired';

export function classifyLifecycle(
  start: string | number,
  end: string | number,
  nowMs: number = Date.now()
): Lifecycle {
  const startMs = typeof start === 'number' ? start : Date.parse(start);
  const endMs = typeof end === 'number' ? end : Date.parse(end);
  if (Number.isNaN(startMs) || Number.isNaN(endMs)) return 'Not started';
  if (nowMs < startMs) return 'Not started';
  if (nowMs > endMs) return 'Expired';
  return 'Active';
}
