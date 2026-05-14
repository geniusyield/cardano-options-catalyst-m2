import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { ConnectedWallet, connectWallet, listAvailableWallets } from './wallet';

interface WalletCtxValue {
  wallet: ConnectedWallet | null;
  connecting: boolean;
  available: { id: string; name: string }[];
  connect: (id: string) => Promise<void>;
  disconnect: () => void;
  error: string | null;
}

const WalletCtx = createContext<WalletCtxValue | null>(null);

export const WalletProvider = ({ children }: { children: React.ReactNode }) => {
  const [wallet, setWallet] = useState<ConnectedWallet | null>(null);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [available, setAvailable] = useState<{ id: string; name: string }[]>([]);

  useEffect(() => {
    // Wallets inject async on window.cardano — re-scan briefly.
    const scan = () => setAvailable(listAvailableWallets());
    scan();
    const handle = window.setInterval(scan, 1000);
    const stop = window.setTimeout(() => window.clearInterval(handle), 6000);
    return () => {
      window.clearInterval(handle);
      window.clearTimeout(stop);
    };
  }, []);

  const connect = useCallback(async (id: string) => {
    setConnecting(true);
    setError(null);
    try {
      const w = await connectWallet(id);
      setWallet(w);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setConnecting(false);
    }
  }, []);

  const disconnect = useCallback(() => {
    setWallet(null);
    setError(null);
  }, []);

  const value = useMemo<WalletCtxValue>(
    () => ({ wallet, connecting, available, connect, disconnect, error }),
    [wallet, connecting, available, connect, disconnect, error]
  );

  return <WalletCtx.Provider value={value}>{children}</WalletCtx.Provider>;
};

export const useWallet = () => {
  const ctx = useContext(WalletCtx);
  if (!ctx) throw new Error('useWallet must be used inside WalletProvider');
  return ctx;
};
