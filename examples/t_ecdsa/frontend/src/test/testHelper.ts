import { HttpAgent } from '@dfinity/agent';
import { createActor, canisterId } from '../../../declarations/t_ecdsa_backend';
import type { _SERVICE } from '../../../declarations/t_ecdsa_backend/t_ecdsa_backend.did';

/**
 * ローカル環境のICPキャニスターに接続するためのヘルパー関数
 */
export async function createTestActor(): Promise<_SERVICE> {
  // 環境変数からキャニスターIDを取得
  // dfx generate実行後に.envファイルに書き込まれる
  const effectiveCanisterId = canisterId || process.env.CANISTER_ID_T_ECDSA_BACKEND;
  
  if (!effectiveCanisterId) {
    throw new Error('CANISTER_ID_T_ECDSA_BACKEND is not set. Please run "dfx generate" first.');
  }
  
  // ローカル環境のホストとポート
  const host = 'http://127.0.0.1:4943';
  
  // HTTPエージェントを作成
  const agent = await HttpAgent.create({
    host,
  });
  
  // ローカル環境の場合、fetchRootKeyを実行（本番環境では不要）
  await agent.fetchRootKey().catch((err) => {
    console.warn('Unable to fetch root key. Check to ensure that your local replica is running');
    throw err;
  });
  
  // Actorを作成
  const actor = createActor(effectiveCanisterId, { agent });
  
  return actor;
}

