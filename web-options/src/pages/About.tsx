export const About = () => {
  return (
    <>
      <h1 className="page-title">About this demo</h1>
      <p className="page-subtitle">A minimal testnet UI for the GeniusYield Options on Cardano (Catalyst Milestone 2)</p>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>What is this?</h3>
        <p>
          This is a standalone, self-contained UI for end-to-end demonstration of the four
          option-contract flows: <strong>create</strong>, <strong>execute</strong>,{' '}
          <strong>retrieve</strong>, and <strong>cancel early</strong>.
        </p>
        <p>
          It is intentionally separated from the public GeniusYield app — every page lives under
          its own deployment so it can be shared, audited, and demoed independently.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Architecture</h3>
        <ul>
          <li><strong>Haskell builders</strong> — <code>createOption</code>, <code>executeOption</code>, <code>retrieveOption</code>, <code>cancelEarlyOption</code> in <code>Core/src/GeniusYield/Api/DEX/Option.hs</code></li>
          <li><strong>REST API</strong> — Servant routes in <code>Core/src-server-lib/GeniusYield/Server/DEX/Option.hs</code></li>
          <li><strong>Atlas PAB</strong> — transactions composed via <code>runSkeletonI</code>, returned unsigned</li>
          <li><strong>UI (this app)</strong> — React + Vite, talks directly to the Tx Server</li>
          <li><strong>Wallet</strong> — CIP-30 (Nami, Eternl, Lace…); the wallet signs the unsigned tx and submits it</li>
        </ul>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Lifecycle states</h3>
        <p style={{ marginTop: 0 }}>
          <span className="option-status not-started">Not started</span>{' '}
          The option's <code>start</code> time is in the future. Buyers cannot yet execute.
        </p>
        <p>
          <span className="option-status active">Active</span>{' '}
          Within <code>[start, end]</code>. Buyer can exercise. Seller can early-cancel only before <code>cancelCutoff</code>.
        </p>
        <p>
          <span className="option-status expired">Expired</span>{' '}
          The <code>end</code> time has passed. Seller can retrieve the deposit if it was not exercised.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Resources</h3>
        <ul>
          <li><a href="/swagger/index.html" target="_blank" rel="noopener noreferrer">OpenAPI / Swagger docs</a></li>
          <li><a href="https://github.com/geniusyield" target="_blank" rel="noopener noreferrer">GitHub</a></li>
          <li><a href="https://docs.geniusyield.co" target="_blank" rel="noopener noreferrer">Protocol docs</a></li>
        </ul>
      </div>
    </>
  );
};
