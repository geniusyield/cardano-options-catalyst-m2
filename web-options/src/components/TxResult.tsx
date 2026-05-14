import { useEffect, useState } from 'react';

interface TxResultProps {
  txId: string;
  /** Optional label shown above the hash, e.g. "Created" / "Cancelled". */
  label?: string;
}

const CONFIRMATION_SECONDS = 60;

const NETWORK = 'preview'; // change to 'preprod' / '' (mainnet) when needed

export const TxResult = ({ txId, label }: TxResultProps) => {
  const [copied, setCopied] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(CONFIRMATION_SECONDS);

  useEffect(() => {
    setSecondsLeft(CONFIRMATION_SECONDS);
    const id = setInterval(() => {
      setSecondsLeft((s) => (s > 0 ? s - 1 : 0));
    }, 1000);
    return () => clearInterval(id);
  }, [txId]);

  const onCopy = async () => {
    try {
      await navigator.clipboard.writeText(txId);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback: select-all
      const range = document.createRange();
      const span = document.getElementById('tx-hash-' + txId.slice(0, 8));
      if (span) {
        range.selectNodeContents(span);
        const sel = window.getSelection();
        sel?.removeAllRanges();
        sel?.addRange(range);
      }
    }
  };

  const cardanoscanUrl = `https://${NETWORK}.cardanoscan.io/transaction/${txId}`;

  return (
    <div
      className="alert success"
      style={{
        padding: 18,
        borderWidth: 2,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
        <strong style={{ fontSize: 14 }}>
          ✅ {label ?? 'Transaction submitted'}
        </strong>
        <button
          type="button"
          className="btn ghost"
          onClick={onCopy}
          style={{ padding: '6px 12px', fontSize: 12 }}
        >
          {copied ? '✓ Copied' : '📋 Copy hash'}
        </button>
      </div>

      <div className="tx-hash" id={'tx-hash-' + txId.slice(0, 8)} style={{ fontSize: 12, padding: 10, marginTop: 0 }}>
        {txId}
      </div>

      <div style={{ marginTop: 10, display: 'flex', gap: 12, fontSize: 12 }}>
        <a href={cardanoscanUrl} target="_blank" rel="noopener noreferrer">
          🔗 View on Cardanoscan ({NETWORK}) →
        </a>
      </div>

      {secondsLeft > 0 ? (
        <div
          style={{
            marginTop: 12,
            padding: 10,
            borderRadius: 8,
            background: 'rgba(251, 191, 36, 0.10)',
            border: '1px solid rgba(251, 191, 36, 0.35)',
            color: '#ffd591',
            fontSize: 12,
            display: 'flex',
            alignItems: 'center',
            gap: 8,
          }}
        >
          <span style={{ fontSize: 16 }}>⏳</span>
          <span>
            <strong>Wait {secondsLeft}s</strong> for this tx to confirm on-chain before submitting the next one.
            Otherwise the wallet will try to spend the same UTxOs and the network will reject it.
          </span>
        </div>
      ) : (
        <div
          style={{
            marginTop: 12,
            padding: 10,
            borderRadius: 8,
            background: 'rgba(74, 222, 128, 0.10)',
            border: '1px solid rgba(74, 222, 128, 0.35)',
            color: '#b8f0ce',
            fontSize: 12,
          }}
        >
          ✅ Likely confirmed — safe to submit the next transaction.
        </div>
      )}
    </div>
  );
};
