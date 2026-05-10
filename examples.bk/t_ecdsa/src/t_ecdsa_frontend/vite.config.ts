import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { icpBindgen } from '@icp-sdk/bindgen/plugins/vite';
import { config } from 'dotenv';


const __dirname = path.dirname(fileURLToPath(import.meta.url))

// ルートの .env を読み込む
config({ path: path.resolve(__dirname, '../../.env') })

const envVarsToInclude = [
  'DFX_VERSION',
  'DFX_NETWORK',
  'CANISTER_ID_INTERNET_IDENTITY',
  'CANISTER_ID_T_ECDSA_FRONTEND',
  'CANISTER_ID_T_ECDSA_BACKEND',
  'CANISTER_ID',
  'CANISTER_CANDID_PATH',
  'WALLETCONNECT_PROJECT_ID',
]

const processEnvObject: Record<string, string> = {}
for (const key of envVarsToInclude) {
  if (process.env[key] !== undefined) {
    processEnvObject[key] = process.env[key] as string
  }
}

const injectedProcessEnv = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  ...processEnvObject,
}

// https://vitejs.dev/config/
export default defineConfig({
	server: {
		watch: {
			usePolling: true, // Docker/リモート環境でホットリロードを確実に
		},
		// ICPレプリカへのAPIリクエストをプロキシ（CORS回避・同一オリジン化）
		proxy: {
			'/api': {
				target: 'http://127.0.0.1:4943',
				changeOrigin: true,
			},
		},
	},
	plugins: [
		preact({
			prerender: {
				enabled: true,
				renderTarget: '#app',
			},
		}),
		icpBindgen({
			didFile: "../declarations/t_ecdsa_backend/t_ecdsa_backend.did",
			outDir: "./src/bindings",
		}),
		icpBindgen({
			didFile: "../declarations/internet_identity/internet_identity.did",
			outDir: "./src/bindings",
		})
	],
	define: {
    process: JSON.stringify({ env: injectedProcessEnv }),
    'process.env': JSON.stringify(injectedProcessEnv),
  },
});
