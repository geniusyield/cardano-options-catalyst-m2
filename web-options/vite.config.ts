import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    proxy: {
      '/api': {
        target: process.env.OPTIONS_API_URL ?? 'http://127.0.0.1:8082',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
      '/DEX': {
        target: process.env.OPTIONS_API_URL ?? 'http://127.0.0.1:8082',
        changeOrigin: true,
      },
    },
  },
});
