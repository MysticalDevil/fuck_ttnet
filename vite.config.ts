import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  root: resolve(__dirname, "frontend"),
  publicDir: false,
  base: "./",
  build: {
    outDir: resolve(__dirname, "webroot"),
    emptyOutDir: true,
    assetsDir: "assets",
    sourcemap: false,
  },
});
