import { FormEvent, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { api, classifyLifecycle, extractTxCbor, formatAmount, formatToken, OptionInfo } from '../lib/api';
import { useWallet } from '../lib/walletContext';
import { signAndSubmit } from '../lib/wallet';
import { TxResult } from '../components/TxResult';

type Action = 'execute' | 'retrieve' | 'cancel-early';

export const Manage = () => {
  const [params, setParams] = useSearchParams();
  const initialRef = params.get('ref') ?? '';
  const { wallet } = useWallet();

  const [ref, setRef] = useState(initialRef);
  const [option, setOption] = useState<OptionInfo | null>(null);
  const [allOptions, setAllOptions] = useState<OptionInfo[]>([]);
  const [executeAmount, setExecuteAmount] = useState('1');
  const [pending, setPending] = useState<Action | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [txId, setTxId] = useState<string | null>(null);

  useEffect(() => {
    api.list().then(setAllOptions).catch((e) => setError((e as Error).message));
  }, []);

  useEffect(() => {
    if (!ref) {
      setOption(null);
      return;
    }
    const found = allOptions.find((o) => o.opiRef === ref);
    setOption(found ?? null);
  }, [ref, allOptions]);

  const lifecycle = option ? classifyLifecycle(option.opiStart, option.opiEnd) : null;

  const onSelectRef = (e: FormEvent<HTMLSelectElement>) => {
    const v = e.currentTarget.value;
    setRef(v);
    setParams(v ? { ref: v } : {});
    setError(null);
    setTxId(null);
  };

  const run = async (action: Action) => {
    if (!wallet) {
      setError('Connect a wallet first.');
      return;
    }
    if (!ref) {
      setError('Select an option first.');
      return;
    }
    setPending(action);
    setError(null);
    setTxId(null);
    try {
      let res;
      const base = {
        usedAddrs: wallet.usedAddresses,
        change: wallet.changeAddress,
        collateral: wallet.collateral ?? undefined,
      };
      if (action === 'execute') {
        res = await api.execute({ ...base, ref, amount: Number(executeAmount) });
      } else if (action === 'retrieve') {
        res = await api.retrieve({ ...base, ref });
      } else {
        res = await api.cancelEarly({ ...base, ref });
      }
      const txCbor = extractTxCbor(res);
      const id = await signAndSubmit(wallet, txCbor);
      setTxId(id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setPending(null);
    }
  };

  return (
    <>
      <h1 className="page-title">Manage option</h1>
      <p className="page-subtitle">Execute, retrieve, or early-cancel an existing option contract.</p>

      <div className="card">
        <label>Select an option</label>
        <select
          value={ref}
          onChange={onSelectRef}
          style={{
            width: '100%',
            padding: '10px 12px',
            borderRadius: 8,
            border: '1px solid var(--border)',
            background: 'var(--bg-elev)',
            color: 'var(--text)',
            fontSize: 14,
          }}
        >
          <option value="">— pick an open option —</option>
          {allOptions.map((o) => (
            <option key={o.opiRef} value={o.opiRef}>
              {o.opiRef.slice(0, 12)}… · {classifyLifecycle(o.opiStart, o.opiEnd)} · {formatAmount(o.opiDepositAmt, o.opiDepositToken)} → {formatAmount(o.opiPaymentAmt, o.opiPaymentToken)}
            </option>
          ))}
        </select>

        {option && lifecycle && (
          <div style={{ marginTop: 16, padding: 14, background: 'var(--bg-elev)', borderRadius: 10 }}>
            <div className="option-row">
              <span className="k">Status</span>
              <span className="v">{lifecycle}</span>
            </div>
            <div className="option-row">
              <span className="k">Deposit (seller locked)</span>
              <span className="v">{formatAmount(option.opiDepositAmt, option.opiDepositToken)}</span>
            </div>
            <div className="option-row">
              <span className="k">Payment (buyer pays)</span>
              <span className="v">{formatAmount(option.opiPaymentAmt, option.opiPaymentToken)}</span>
            </div>
            <div className="option-row">
              <span className="k">Price</span>
              <span className="v">
                {option.opiPrice} {formatToken(option.opiPaymentToken)} / {formatToken(option.opiDepositToken)}
              </span>
            </div>
            <div className="option-row">
              <span className="k">Window</span>
              <span className="v" style={{ fontSize: 11 }}>
                {fmtTime(option.opiStart)} → {fmtTime(option.opiEnd)}
              </span>
            </div>
            <div className="option-row">
              <span className="k">Cancel cutoff</span>
              <span className="v" style={{ fontSize: 11 }}>{fmtTime(option.opiCancelCutoff)}</span>
            </div>
          </div>
        )}
      </div>

      {error && <div className="alert error">{error}</div>}
      {txId && <TxResult txId={txId} label="Action submitted" />}

      <div className="row">
        <div className="card">
          <h3 style={{ marginTop: 0 }}>🪙 Execute (buyer)</h3>
          <p style={{ color: 'var(--text-dim)', fontSize: 13, marginTop: 0 }}>
            Exercise this option within its valid window. You pay the price and receive the deposit.
          </p>
          <label>Amount</label>
          <input
            type="number"
            min={1}
            value={executeAmount}
            onChange={(e) => setExecuteAmount(e.target.value)}
          />
          <button
            className="btn"
            onClick={() => run('execute')}
            disabled={!wallet || !ref || pending !== null || lifecycle !== 'Active'}
            style={{ marginTop: 12, width: '100%' }}
          >
            {pending === 'execute' && <span className="spinner" />}
            {pending === 'execute' ? 'Executing…' : 'Execute option'}
          </button>
          <div style={{ marginTop: 10, fontSize: 11, color: 'var(--text-dim)', lineHeight: 1.4 }}>
            Note: the buyer wallet must hold the option NFT. The seller transfers
            it via the standard secondary market (DEX, OTC, etc.) before exercise.
          </div>
        </div>

        <div className="card">
          <h3 style={{ marginTop: 0 }}>📤 Retrieve (seller)</h3>
          <p style={{ color: 'var(--text-dim)', fontSize: 13, marginTop: 0 }}>
            After expiry, the seller can retrieve the deposit (if not exercised).
          </p>
          <button
            className="btn"
            onClick={() => run('retrieve')}
            disabled={!wallet || !ref || pending !== null || lifecycle !== 'Expired'}
            style={{ marginTop: 12, width: '100%' }}
          >
            {pending === 'retrieve' && <span className="spinner" />}
            {pending === 'retrieve' ? 'Retrieving…' : 'Retrieve deposit'}
          </button>
        </div>

        <div className="card">
          <h3 style={{ marginTop: 0 }}>↩️ Cancel early (seller)</h3>
          <p style={{ color: 'var(--text-dim)', fontSize: 13, marginTop: 0 }}>
            Before the cancel cutoff, the seller can withdraw the option and recover the deposit.
          </p>
          <button
            className="btn danger"
            onClick={() => run('cancel-early')}
            disabled={!wallet || !ref || pending !== null}
            style={{ marginTop: 12, width: '100%' }}
          >
            {pending === 'cancel-early' && <span className="spinner" />}
            {pending === 'cancel-early' ? 'Cancelling…' : 'Cancel early'}
          </button>
        </div>
      </div>
    </>
  );
};

function fmtTime(t: string | number): string {
  const ms = typeof t === 'number' ? t : Date.parse(t);
  if (Number.isNaN(ms)) return String(t);
  const d = new Date(ms);
  return `${d.toLocaleDateString()} ${d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}
