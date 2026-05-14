import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, classifyLifecycle, formatAmount, formatToken, OptionInfo } from '../lib/api';

export const Browse = () => {
  const [options, setOptions] = useState<OptionInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = async () => {
    setLoading(true);
    setError(null);
    try {
      const list = await api.list();
      setOptions(list);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refresh();
  }, []);

  return (
    <>
      <h1 className="page-title">Open option contracts</h1>
      <p className="page-subtitle">All option contracts currently locked in the script. Click an option to act on it.</p>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <Link to="/create" className="btn">+ Create new option</Link>
        <button className="btn ghost" onClick={refresh}>↻ Refresh</button>
      </div>

      {error && <div className="alert error">Failed to load options: {error}</div>}

      {loading ? (
        <div className="empty"><span className="spinner" />Loading…</div>
      ) : options.length === 0 ? (
        <div className="empty">
          <div className="emoji">📭</div>
          <div style={{ fontSize: 16, fontWeight: 600 }}>No open options yet</div>
          <div style={{ marginTop: 6 }}>Create the first one to get started.</div>
        </div>
      ) : (
        <div className="option-grid">
          {options.map((opt) => (
            <OptionCard key={opt.opiRef} opt={opt} />
          ))}
        </div>
      )}
    </>
  );
};

const OptionCard = ({ opt }: { opt: OptionInfo }) => {
  const lifecycle = classifyLifecycle(opt.opiStart, opt.opiEnd);
  const statusClass =
    lifecycle === 'Not started' ? 'not-started' : lifecycle === 'Active' ? 'active' : 'expired';

  return (
    <div className="option-card">
      <span className={`option-status ${statusClass}`}>{lifecycle}</span>

      <div className="option-row">
        <span className="k">Option ref</span>
        <span className="v" style={{ fontFamily: 'monospace', fontSize: 11 }}>
          {opt.opiRef.slice(0, 10)}…{opt.opiRef.slice(-8)}
        </span>
      </div>
      <div className="option-row">
        <span className="k">Deposit (locked)</span>
        <span className="v">{formatAmount(opt.opiDepositAmt, opt.opiDepositToken)}</span>
      </div>
      <div className="option-row">
        <span className="k">Payment (to exercise)</span>
        <span className="v">{formatAmount(opt.opiPaymentAmt, opt.opiPaymentToken)}</span>
      </div>
      <div className="option-row">
        <span className="k">Price</span>
        <span className="v">
          {opt.opiPrice} {formatToken(opt.opiPaymentToken)} / {formatToken(opt.opiDepositToken)}
        </span>
      </div>
      <div className="option-row">
        <span className="k">Window</span>
        <span className="v" style={{ fontSize: 11 }}>
          {fmtTime(opt.opiStart)} → {fmtTime(opt.opiEnd)}
        </span>
      </div>

      <div className="option-actions">
        <Link to={`/manage?ref=${encodeURIComponent(opt.opiRef)}`} className="btn">Manage →</Link>
      </div>
    </div>
  );
};

function fmtTime(t: string | number): string {
  const ms = typeof t === 'number' ? t : Date.parse(t);
  if (Number.isNaN(ms)) return String(t);
  const d = new Date(ms);
  return `${d.toLocaleDateString()} ${d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}
