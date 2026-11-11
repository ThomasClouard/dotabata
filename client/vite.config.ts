import { defineConfig } from 'vite';

// En développement, Vite sert le client sur le port 5173 et relaie le WebSocket vers le serveur de jeu (3000).
export default defineConfig({
  server: {
    host: true,
    port: 5173,
    strictPort: true,
    fs: { allow: ['..'] },
    proxy: { '/ws': { target: 'ws://127.0.0.1:3000', ws: true } },
  },
  build: { outDir: 'dist', emptyOutDir: true, chunkSizeWarningLimit: 1200 },
});
