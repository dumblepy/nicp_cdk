/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** 本番では `ic`、ローカルでは省略または `local`（II は `http://id.ai.localhost:8000/#authorize`） */
  readonly VITE_IC_NETWORK?: string;
  /** 上書き用。未指定時は `examples/vetkey/.icp/cache/mappings/local.ids.json` の `backend` を使う */
  readonly VITE_BACKEND_CANISTER_ID?: string;
  /** 上書き用。未指定時は `.icp/cache/networks/local/descriptor.json` の `root-key` */
  readonly VITE_IC_ROOT_KEY_HEX?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
