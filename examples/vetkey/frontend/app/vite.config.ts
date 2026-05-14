/// <reference types="vite/client" />
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { icpBindgen } from "@icp-sdk/bindgen/plugins/vite";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** `examples/vetkey`（`frontend/app` から 2 つ上） */
const vetkeyProjectRoot = path.resolve(__dirname, "../..");

function readJsonFile<T>(filePath: string): T | null {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8")) as T;
  } catch {
    return null;
  }
}

/**
 * icp のローカル成果物から backend ID とルート鍵を解決する。
 * `descriptor.json` の `proxy-canister-id`（例: txyno-…）はゲートウェイ用で backend ではないため使わない。
 */
function resolveLocalIcpDevEnv(): {
  backendCanisterId: string | null;
  icRootKeyHex: string | null;
} {
  const descriptor = readJsonFile<{ "root-key"?: string }>(
    path.join(
      vetkeyProjectRoot,
      ".icp/cache/networks/local/descriptor.json",
    ),
  );
  const mappings = readJsonFile<{ backend?: string }>(
    path.join(vetkeyProjectRoot, ".icp/cache/mappings/local.ids.json"),
  );
  return {
    backendCanisterId: mappings?.backend?.trim() ?? null,
    icRootKeyHex: descriptor?.["root-key"]?.trim() ?? null,
  };
}

const FALLBACK_IC_ROOT_KEY_HEX =
  "308182301d060d2b0601040182dc7c0503010201060c2b0601040182dc7c050302010361008b52b4994f94c7ce4be1c1542d7c81dc79fea17d49efe8fa42e8566373581d4b969c4a59e96a0ef51b711fe5027ec01601182519d0a788f4bfe388e593b97cd1d7e44904de79422430bca686ac8c21305b3397b5ba4d7037d17877312fb7ee34";

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, __dirname, "");
  const local = resolveLocalIcpDevEnv();

  const BACKEND_CANISTER_ID =
    env.VITE_BACKEND_CANISTER_ID?.trim() ||
    local.backendCanisterId ||
    "txyno-ch777-77776-aaaaq-cai";

  const IC_ROOT_KEY_HEX =
    env.VITE_IC_ROOT_KEY_HEX?.trim() ||
    local.icRootKeyHex ||
    FALLBACK_IC_ROOT_KEY_HEX;

  if (!local.backendCanisterId && !env.VITE_BACKEND_CANISTER_ID?.trim()) {
    console.warn(
      "[vetkey frontend] `.icp/cache/mappings/local.ids.json` が無いか backend 未定義です。`icp deploy` 後に再実行するか、`VITE_BACKEND_CANISTER_ID` を .env に設定してください。暫定 ID で起動します:",
      BACKEND_CANISTER_ID,
    );
  }

  return {
    plugins: [
      react(),
      icpBindgen({
        didFile: "../../backend/backend.did",
        outDir: "./src/backend/api",
      }),
    ],
    server: {
      host: "0.0.0.0",
      watch: {
        usePolling: true,
      },
      headers: {
        "Set-Cookie": `ic_env=${encodeURIComponent(
          `ic_root_key=${IC_ROOT_KEY_HEX}&PUBLIC_CANISTER_ID:backend=${BACKEND_CANISTER_ID}`,
        )}; SameSite=Lax;`,
      },
      proxy: {
        "/api": {
          target: "http://127.0.0.1:8000",
          changeOrigin: true,
        },
      },
    },
  };
});
