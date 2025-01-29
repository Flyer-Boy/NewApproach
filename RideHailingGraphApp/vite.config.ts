import { defineConfig } from "vite";
import svgr from "vite-plugin-svgr";
import react from "@vitejs/plugin-react-swc";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    react(),
    svgr({
      include: "**/*.svg?react",
    }),
  ],
  resolve: {
    alias: {
      "@ride-hailing": "/src",
    },
  },
  server: {
    host: true,
    port: 3031,
    open: true,
  },
  preview: {
    port: 3031,
  },
});
