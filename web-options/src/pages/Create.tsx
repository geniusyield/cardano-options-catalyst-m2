import { FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, extractTxCbor } from '../lib/api';
import { useWallet } from '../lib/walletContext';
import { signAndSubmit } from '../lib/wallet';
import { TxResult } from '../components/TxResult';

const isoLocal = (d: Date) => {
  const off = d.getTimezoneOffset();
  const local = new Date(d.getTime() - off * 60_000);
  return local.toISOString().slice(0, 16);
};

const minsFromNow = (mins: number) => isoLocal(new Date(Date.now() + mins * 60_000));

interface Preset {
  id: string;
  label: string;
  description: string;
  emoji: string;
  values: () => { start: string; end: string; cancelCutoff: string };
}

const PRESETS: Preset[] = [
  {
    id: 'cancel-early',
    label: 'For Cancel-Early demo',
    description: 'Cutoff in 4 min — sign now, then cancel before cutoff.',
    emoji: '↩️',
    values: () => ({
      start: minsFromNow(5),
      end: minsFromNow(60),
      cancelCutoff: minsFromNow(4),
    }),
  },
  {
    id: 'execute',
    label: 'For Execute demo',
    description: 'Active right after confirmation — buyer can exercise immediately.',
    emoji: '🪙',
    values: () => ({
      start: minsFromNow(-2),
      end: minsFromNow(60),
      cancelCutoff: minsFromNow(-1),
    }),
  },
  {
    id: 'retrieve',
    label: 'For Retrieve demo',
    description: 'Expires in 3 min — wait, then seller retrieves the deposit.',
    emoji: '📤',
    values: () => ({
      start: minsFromNow(-2),
      end: minsFromNow(3),
      cancelCutoff: minsFromNow(-5),
    }),
  },
];

const defaults = PRESETS[0].values();

export const Create = () => {
  const { wallet } = useWallet();
  const nav = useNavigate();

  const [start, setStart] = useState(defaults.start);
  const [end, setEnd] = useState(defaults.end);
  const [cancelCutoff, setCancelCutoff] = useState(defaults.cancelCutoff);
  const [depositSymbol, setDepositSymbol] = useState('');
  const [depositToken, setDepositToken] = useState('');
  const [paymentSymbol, setPaymentSymbol] = useState('');
  const [paymentToken, setPaymentToken] = useState('');
  const [price, setPrice] = useState('1.0');
  const [amount, setAmount] = useState('100');

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txId, setTxId] = useState<string | null>(null);
  const [activePreset, setActivePreset] = useState<string | null>('cancel-early');

  const applyPreset = (preset: Preset) => {
    const v = preset.values();
    setStart(v.start);
    setEnd(v.end);
    setCancelCutoff(v.cancelCutoff);
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
    try {
      const res = await api.create({
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
      });

      const txCbor = extractTxCbor(res);
      const id = await signAndSubmit(wallet, txCbor);
      setTxId(id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <h1 className="page-title">Create new option</h1>
      <p className="page-subtitle">Define the option's window, deposit, payment, and price. The unsigned tx is built server-side and signed by your wallet.</p>

      {!wallet && (
        <div className="alert info">Connect a Cardano wallet to enable submission. You can still preview the form below.</div>
      )}

      <div className="card">
        <h3 style={{ marginTop: 0, color: 'var(--text-soft)' }}>Quick presets</h3>
        <p style={{ color: 'var(--text-dim)', fontSize: 13, marginTop: 0, marginBottom: 14 }}>
          One-click setups for each Catalyst M2 demo flow.
        </p>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
          {PRESETS.map((preset) => {
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

        <h3 style={{ color: 'var(--text-soft)' }}>Deposit asset (what the seller locks)</h3>
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

        <h3 style={{ color: 'var(--text-soft)' }}>Payment asset (what the buyer pays)</h3>
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
            <input value={price} onChange={(e) => setPrice(e.target.value)} placeholder="1.0" required />
          </div>
          <div>
            <label>Amount (units)</label>
            <input type="number" min={1} value={amount} onChange={(e) => setAmount(e.target.value)} required />
          </div>
        </div>

        {error && <div className="alert error" style={{ marginTop: 16 }}>{error}</div>}
        {txId && (
          <div style={{ marginTop: 16 }}>
            <TxResult txId={txId} label="Option created" />
          </div>
        )}

        <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
          <button type="submit" className="btn" disabled={submitting || !wallet}>
            {submitting && <span className="spinner" />}
            {submitting ? 'Building & signing…' : 'Create option'}
          </button>
          <button type="button" className="btn ghost" onClick={() => nav('/')}>Cancel</button>
        </div>
      </form>
    </>
  );
};
