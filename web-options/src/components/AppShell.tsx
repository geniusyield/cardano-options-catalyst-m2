import { NavLink, Outlet } from 'react-router-dom';
import { useWallet } from '../lib/walletContext';
import { shortAddr } from '../lib/wallet';

export const AppShell = () => {
  const { wallet, connect, disconnect, available, connecting, error } = useWallet();

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <div className="logo">
            <span>GeniusYield</span>
            <span className="badge">OPTIONS · TESTNET</span>
          </div>

          <nav className="nav">
            <NavLink to="/" end>Browse</NavLink>
            <NavLink to="/create">Create</NavLink>
            <NavLink to="/create-cip68">Create (CIP-68)</NavLink>
            <NavLink to="/manage">Manage</NavLink>
            <NavLink to="/about">About</NavLink>
          </nav>

          <WalletButton
            wallet={wallet}
            available={available}
            onConnect={connect}
            onDisconnect={disconnect}
            connecting={connecting}
            error={error}
          />
        </div>
      </header>

      <main className="main">
        <Outlet />
      </main>

      <footer className="footer">
        Cardano testnet demo · funded by{' '}
        <a href="https://projectcatalyst.io" target="_blank" rel="noopener noreferrer">Project Catalyst</a>{' '}
        · <a href="/swagger/index.html" target="_blank" rel="noopener noreferrer">API docs</a>
      </footer>
    </div>
  );
};

interface WalletButtonProps {
  wallet: ReturnType<typeof useWallet>['wallet'];
  available: { id: string; name: string }[];
  onConnect: (id: string) => void;
  onDisconnect: () => void;
  connecting: boolean;
  error: string | null;
}

const WalletButton = ({ wallet, available, onConnect, onDisconnect, connecting, error }: WalletButtonProps) => {
  if (wallet) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span className="wallet-pill connected">
          <span className="dot" />
          {wallet.name} · {shortAddr(wallet.changeAddress)}
        </span>
        <button className="btn ghost" onClick={onDisconnect}>Disconnect</button>
      </div>
    );
  }

  if (connecting) {
    return <span className="wallet-pill"><span className="spinner" />Connecting…</span>;
  }

  if (available.length === 0) {
    return (
      <span className="wallet-pill disconnected" title={error ?? 'Install a CIP-30 wallet (Nami, Eternl, Lace…)'}>
        <span className="dot" /> No wallet detected
      </span>
    );
  }

  return (
    <div style={{ position: 'relative' }}>
      <details>
        <summary className="btn ghost" style={{ listStyle: 'none', cursor: 'pointer' }}>
          Connect wallet ▾
        </summary>
        <div style={{
          position: 'absolute',
          top: 'calc(100% + 6px)',
          right: 0,
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 10,
          padding: 6,
          zIndex: 10,
          minWidth: 160,
          boxShadow: '0 8px 24px rgba(0,0,0,0.4)',
        }}>
          {available.map((w) => (
            <button
              key={w.id}
              onClick={() => onConnect(w.id)}
              style={{
                display: 'block',
                width: '100%',
                textAlign: 'left',
                padding: '8px 12px',
                background: 'transparent',
                color: 'var(--text)',
                border: 'none',
                borderRadius: 6,
                fontSize: 13,
                fontWeight: 600,
              }}
              onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--bg-elev)')}
              onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
            >
              {w.name}
            </button>
          ))}
        </div>
      </details>
    </div>
  );
};
