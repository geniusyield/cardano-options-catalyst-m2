import { FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, extractTxCbor, CreateCIP68Params } from '../lib/api';
import { useWallet } from '../lib/walletContext';
import { signAndSubmit } from '../lib/wallet';
import { TxResult } from '../components/TxResult';

// Local helper — formats a Date as a `datetime-local` value in the user's zone.
const isoLocal = (d: Date) => {
  const off = d.getTimezoneOffset();
  const local = new Date(d.getTime() - off * 60_000);
  return local.toISOString().slice(0, 16);
};

const minsFromNow = (mins: number) => isoLocal(new Date(Date.now() + mins * 60_000));

// GENS on Cardano mainnet — replace with your preview testnet equivalent if
// you don't hold GENS on preview. The CIP-68 demo focuses on metadata
// rendering, not on the underlying asset.
const GENS_POLICY = 'dda5fdb1002f7389b33e036b6afee82a8189becb6cba852e8b79b4fb';
const GENS_ASSET_HEX = '0014df1047454e53';

interface DemoPreset {
  id: string;
  label: string;
  description: string;
  emoji: string;
  // Returns a full param payload minus the wallet bits (which come from CIP-30).
  values: () => Omit<CreateCIP68Params, 'usedAddrs' | 'change' | 'collateral'>;
}

const DEMO_PRESETS: DemoPreset[] = [
  {
    id: 'call-demo',
    label: 'M3 Call demo · ADA→GENS @ 0.5',
    description: 'European-style call · cancellable · active right after confirmation.',
    emoji: '📈',
    values: () => ({
      start: new Date(Date.now() - 2 * 60_000).toISOString(),
      end: new Date(Date.now() + 60 * 60_000).toISOString(),
      cancelCutoff: new Date(Date.now() + 5 * 60_000).toISOString(),
      depositSymbol: '',
      depositToken: '',
      paymentSymbol: GENS_POLICY,
      paymentToken: GENS_ASSET_HEX,
      price: '0.5',
      amount: 10,
      optionType: 'call',
      cancellable: true,
      displayName: 'GeniusYield ADA→GENS Call · 0.5',
      imageUri: 'data:image/svg+xml;base64,PLACEHOLDER_LOGO',
      description:
        'European-style call option: the buyer may exchange ADA for GENS at strike 0.5 within the active window. Cancellable by the seller before the cutoff.',
      feeCfgRef: '',
    }),
  },
  {
    id: 'put-demo',
    label: 'M3 Put demo · GENS→ADA @ 0.6',
    description: 'European-style put · non-cancellable · active right after confirmation.',
    emoji: '📉',
    values: () => ({
      start: new Date(Date.now() - 2 * 60_000).toISOString(),
      end: new Date(Date.now() + 60 * 60_000).toISOString(),
      cancelCutoff: new Date(Date.now() - 60_000).toISOString(),
      depositSymbol: GENS_POLICY,
      depositToken: GENS_ASSET_HEX,
      paymentSymbol: '',
      paymentToken: '',
      price: '0.6',
      amount: 10,
      optionType: 'put',
      cancellable: false,
      displayName: 'GeniusYield GENS→ADA Put · 0.6',
      imageUri: 'data:image/svg+xml;base64,PLACEHOLDER_LOGO',
      description:
        'European-style put option: the buyer may exchange GENS for ADA at strike 0.6 within the active window. Non-cancellable once minted.',
      feeCfgRef: '',
    }),
  },
];

const defaults = DEMO_PRESETS[0].values();

export const CreateCIP68 = () => {
  const { wallet } = useWallet();
  const nav = useNavigate();

  const [start, setStart] = useState(isoLocal(new Date(defaults.start)));
  const [end, setEnd] = useState(isoLocal(new Date(defaults.end)));
  const [cancelCutoff, setCancelCutoff] = useState(isoLocal(new Date(defaults.cancelCutoff)));
  const [depositSymbol, setDepositSymbol] = useState(defaults.depositSymbol);
  const [depositToken, setDepositToken] = useState(defaults.depositToken);
  const [paymentSymbol, setPaymentSymbol] = useState(defaults.paymentSymbol);
  const [paymentToken, setPaymentToken] = useState(defaults.paymentToken);
  const [price, setPrice] = useState(String(defaults.price));
  const [amount, setAmount] = useState(String(defaults.amount));
  const [optionType, setOptionType] = useState<'call' | 'put'>(defaults.optionType);
  const [cancellable, setCancellable] = useState<boolean>(defaults.cancellable);
  const [displayName, setDisplayName] = useState(defaults.displayName);
  const [imageUri, setImageUri] = useState(defaults.imageUri);
  const [description, setDescription] = useState(defaults.description);
  const [feeCfgRef, setFeeCfgRef] = useState(defaults.feeCfgRef);

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txId, setTxId] = useState<string | null>(null);
  const [refAsset, setRefAsset] = useState<string | null>(null);
  const [refAddress, setRefAddress] = useState<string | null>(null);
  const [activePreset, setActivePreset] = useState<string | null>('call-demo');

  const applyPreset = (preset: DemoPreset) => {
    const v = preset.values();
    setStart(isoLocal(new Date(v.start)));
    setEnd(isoLocal(new Date(v.end)));
    setCancelCutoff(isoLocal(new Date(v.cancelCutoff)));
    setDepositSymbol(v.depositSymbol);
    setDepositToken(v.depositToken);
    setPaymentSymbol(v.paymentSymbol);
    setPaymentToken(v.paymentToken);
    setPrice(String(v.price));
    setAmount(String(v.amount));
    setOptionType(v.optionType);
    setCancellable(v.cancellable);
    setDisplayName(v.displayName);
    setImageUri(v.imageUri);
    setDescription(v.description);
    setFeeCfgRef(v.feeCfgRef);
    setActivePreset(preset.id);
  };

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!wallet) {
      setError('Please connect a wallet first.');
      return;
    }
    setSubmitting(true);
    setError(null);
    setTxId(null);
    setRefAsset(null);
    setRefAddress(null);
    try {
      const res = await api.createCIP68({
        usedAddrs: wallet.usedAddresses,
        change: wallet.changeAddress,
        collateral: wallet.collateral ?? undefined,
        start: new Date(start).toISOString(),
        end: new Date(end).toISOString(),
        cancelCutoff: new Date(cancelCutoff).toISOString(),
        depositSymbol: depositSymbol.trim(),
        depositToken: depositToken.trim(),
        paymentSymbol: paymentSymbol.trim(),
        paymentToken: paymentToken.trim(),
        price,
        amount: Number(amount),
        optionType,
        cancellable,
        displayName,
        imageUri,
        description,
        feeCfgRef,
      });

      setRefAsset(res.cip68ReferenceAsset);
      setRefAddress(res.cip68ReferenceAddress);

      const txCbor = extractTxCbor(res);
      const id = await signAndSubmit(wallet, txCbor);
      setTxId(id);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <h1 className="page-title">Create CIP-68 option series</h1>
      <p className="page-subtitle">
        Same on-chain option as the regular Create page, plus a paired CIP-68 reference/user NFT
        with inline metadata so wallets (Lace, Eternl, pool.pm) render the series as a proper NFT.
      </p>

      {!wallet && (
        <div className="alert info">Connect a Cardano wallet to enable submission.</div>
      )}

      <div className="card">
        <h3 style={{ marginTop: 0, color: 'var(--text-soft)' }}>Catalyst M3 demo presets</h3>
        <p style={{ color: 'var(--text-dim)', fontSize: 13, marginTop: 0, marginBottom: 14 }}>
          One-click setups for the two M3 acceptance-criteria demo series.
        </p>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 10 }}>
          {DEMO_PRESETS.map((preset) => {
            const active = activePreset === preset.id;
            return (
              <button
                key={preset.id}
                type="button"
                onClick={() => applyPreset(preset)}
                style={{
                  padding: '12px 14px',
                  borderRadius: 10,
                  border: active ? '1px solid var(--accent)' : '1px solid var(--border)',
                  background: active ? 'rgba(76, 84, 245, 0.12)' : 'var(--bg-elev)',
                  color: 'var(--text)',
                  cursor: 'pointer',
                  textAlign: 'left',
                  fontFamily: 'inherit',
                  transition: 'border-color 0.15s ease, background 0.15s ease',
                }}
              >
                <div style={{ fontSize: 18, marginBottom: 4 }}>{preset.emoji}</div>
                <div style={{ fontWeight: 700, fontSize: 13, marginBottom: 4 }}>{preset.label}</div>
                <div style={{ fontSize: 11, color: 'var(--text-dim)', lineHeight: 1.4 }}>
                  {preset.description}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      <form onSubmit={onSubmit} className="card">
        <h3 style={{ marginTop: 0, color: 'var(--text-soft)' }}>Window</h3>
        <div className="row three">
          <div>
            <label>Start</label>
            <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} required />
          </div>
          <div>
            <label>End</label>
            <input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} required />
          </div>
          <div>
            <label>Early-cancel cutoff</label>
            <input type="datetime-local" value={cancelCutoff} onChange={(e) => setCancelCutoff(e.target.value)} required />
          </div>
        </div>

        <h3 style={{ color: 'var(--text-soft)' }}>Deposit asset (seller locks)</h3>
        <div className="row">
          <div>
            <label>Symbol (policy id, hex)</label>
            <input value={depositSymbol} onChange={(e) => setDepositSymbol(e.target.value)} placeholder="empty for ADA" />
          </div>
          <div>
            <label>Token (asset name, hex)</label>
            <input value={depositToken} onChange={(e) => setDepositToken(e.target.value)} placeholder="empty for ADA" />
          </div>
        </div>

        <h3 style={{ color: 'var(--text-soft)' }}>Payment asset (buyer pays)</h3>
        <div className="row">
          <div>
            <label>Symbol (policy id, hex)</label>
            <input value={paymentSymbol} onChange={(e) => setPaymentSymbol(e.target.value)} placeholder="empty for ADA" />
          </div>
          <div>
            <label>Token (asset name, hex)</label>
            <input value={paymentToken} onChange={(e) => setPaymentToken(e.target.value)} placeholder="empty for ADA" />
          </div>
        </div>

        <h3 style={{ color: 'var(--text-soft)' }}>Pricing</h3>
        <div className="row">
          <div>
            <label>Price (payment per deposit)</label>
            <input value={price} onChange={(e) => setPrice(e.target.value)} placeholder="0.5" required />
          </div>
          <div>
            <label>Amount (units)</label>
            <input type="number" min={1} value={amount} onChange={(e) => setAmount(e.target.value)} required />
          </div>
        </div>

        <h3 style={{ color: 'var(--text-soft)' }}>CIP-68 metadata</h3>
        <div className="row">
          <div>
            <label>Option type</label>
            <select
              value={optionType}
              onChange={(e) => setOptionType(e.target.value as 'call' | 'put')}
            >
              <option value="call">Call</option>
              <option value="put">Put</option>
            </select>
          </div>
          <div>
            <label>
              <input
                type="checkbox"
                checked={cancellable}
                onChange={(e) => setCancellable(e.target.checked)}
                style={{ marginRight: 8 }}
              />
              Cancellable
            </label>
          </div>
        </div>
        <div>
          <label>Display name</label>
          <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} required />
        </div>
        <div>
          <label>Image URI (data:… or ipfs:…)</label>
          <input value={imageUri} onChange={(e) => setImageUri(e.target.value)} required />
        </div>
        <div>
          <label>Description</label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
            required
          />
        </div>
        <div>
          <label>Fee-config NFT reference (optional)</label>
          <input
            value={feeCfgRef}
            onChange={(e) => setFeeCfgRef(e.target.value)}
            placeholder="policyId.assetName, or empty for none"
          />
        </div>

        {error && <div className="alert error" style={{ marginTop: 16 }}>{error}</div>}

        {(refAsset || refAddress) && (
          <div className="alert info" style={{ marginTop: 16 }}>
            <strong>Reference NFT</strong>
            <div style={{ fontFamily: 'monospace', fontSize: 12, marginTop: 6, wordBreak: 'break-all' }}>
              {refAsset && <div><span style={{ color: 'var(--text-dim)' }}>asset:</span> {refAsset}</div>}
              {refAddress && <div><span style={{ color: 'var(--text-dim)' }}>address:</span> {refAddress}</div>}
            </div>
          </div>
        )}

        {txId && (
          <div style={{ marginTop: 16 }}>
            <TxResult txId={txId} label="CIP-68 option series minted" />
          </div>
        )}

        <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
          <button type="submit" className="btn" disabled={submitting || !wallet}>
            {submitting && <span className="spinner" />}
            {submitting ? 'Building & signing…' : 'Mint CIP-68 series'}
          </button>
          <button type="button" className="btn ghost" onClick={() => nav('/')}>
            Cancel
          </button>
        </div>
      </form>
    </>
  );
};
