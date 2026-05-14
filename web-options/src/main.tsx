import ReactDOM from 'react-dom/client';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { WalletProvider } from './lib/walletContext';
import { Browse } from './pages/Browse';
import { Create } from './pages/Create';
import { CreateCIP68 } from './pages/CreateCIP68';
import { Manage } from './pages/Manage';
import { About } from './pages/About';
import './styles/index.css';

// React.StrictMode intentionally double-invokes effects in dev — disabled here
// to avoid noisy double-render side-effects during the Catalyst M2 screencast.
ReactDOM.createRoot(document.getElementById('root')!).render(
  <WalletProvider>
    <BrowserRouter>
      <Routes>
        <Route element={<AppShell />}>
          <Route index element={<Browse />} />
          <Route path="create" element={<Create />} />
          <Route path="create-cip68" element={<CreateCIP68 />} />
          <Route path="manage" element={<Manage />} />
          <Route path="about" element={<About />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </WalletProvider>
);
