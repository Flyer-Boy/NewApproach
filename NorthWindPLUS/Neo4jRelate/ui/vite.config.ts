import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In development the UI runs on Vite's server and sends /api to the Python API (uvicorn api.main:app --port 8000).
// `npm run build` writes dist/, which the API serves itself at http://localhost:8000.
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, proxy: { "/api": "http://localhost:8000" } },
  build: { chunkSizeWarningLimit: 1000 },   // Chakra UI is most of the bundle; one chunk is fine for a local tool
});
