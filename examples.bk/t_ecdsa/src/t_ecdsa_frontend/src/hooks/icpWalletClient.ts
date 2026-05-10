import {
  type Address,
  type Chain,
  type Hex,
  type LocalAccount,
  type RpcSchema,
  type SerializeTransactionFn,
  type SignableMessage,
  type Signature,
  type TransactionSerializable,
  type TypedData,
  type TypedDataDefinition,
  type WalletClient,
  type HttpTransport,
  createWalletClient,
  http,
  keccak256,
  serializeTransaction,
  hashMessage,
  serializeSignature,
  hexToBytes,
} from 'viem';
import { toAccount } from 'viem/accounts';
import { AuthClient } from '@icp-sdk/auth/client';
import { HttpAgent } from '@icp-sdk/core/agent';
import { createActor } from "../bindings/t_ecdsa_backend";


const toIcpAccount = async (authClient: AuthClient): Promise<LocalAccount> => {
  const canisterId = process.env.CANISTER_ID_T_ECDSA_BACKEND;
  if (!canisterId) {
    throw new Error('CANISTER_ID_T_ECDSA_BACKEND is not set');
  }
  // 開発時はViteプロキシ経由で同一オリジンにし、本番はレプリカ直指定
  const isLocal =
    process.env.DFX_NETWORK === 'local' ||
    typeof process !== 'undefined' &&
      process.env?.NODE_ENV === 'development';
  const host =
    typeof window !== 'undefined' && isLocal
      ? window.location.origin // Viteの/apiプロキシ経由でレプリカへ
      : 'http://127.0.0.1:4943';
  const identity = authClient.getIdentity();
  const agent = await HttpAgent.create({
    identity,
    host,
    shouldFetchRootKey: isLocal,
  });

  const actor = createActor(canisterId, { agent });
  // 公開鍵が未生成だとgetEvmAddressは空を返すため、先に生成する
  await actor.getNewPublicKey();
  const rawAddress = await actor.getEvmAddress();
  const address = (typeof rawAddress === 'string' ? rawAddress : String(rawAddress)).trim();
  if (!address || address.length !== 42 || !/^0x[0-9a-fA-F]{40}$/.test(address)) {
    throw new Error(
      `Invalid EVM address from canister: "${rawAddress}". ` +
        'Ensure the local replica is running (dfx start) and the backend canister is deployed.'
    );
  }
  const evmAddress = address as Address;

  const signMessage = async ({
    message,
  }: {
    message: SignableMessage;
  }): Promise<Hex> => {
    const hash = hashMessage(message);
    const hashBytes = hexToBytes(hash);
    const signature = await actor.signWithEvmWallet(hashBytes);
    
    // 0xプレフィックスを削除
    const sigHex = signature.startsWith('0x') ? signature.slice(2) : signature;
    
    // 署名は65バイト (130文字) である必要がある
    if (sigHex.length !== 130) {
      throw new Error(`Invalid signature length: ${sigHex.length}, expected 130`);
    }
    
    const r = '0x' + sigHex.slice(0, 64);
    const s = '0x' + sigHex.slice(64, 128);
    let v = parseInt(sigHex.slice(128, 130), 16);
    
    // Ethereumの署名では、v値は27または28である必要がある
    // recovery IDが0または1の場合、27を加算する
    if (v < 27) {
      v += 27;
    }
    
    console.log('Parsed signature - r:', r, 's:', s, 'v:', v);
    
    const sig: Signature = {
      r: r as Hex,
      s: s as Hex,
      v: BigInt(v),
    };
    
    return serializeSignature(sig);
  };

  const signTransaction = async<
    TTransactionSerializable extends TransactionSerializable,
  >(
    transaction: TTransactionSerializable,
    args?: {
      serializer?: SerializeTransactionFn<TTransactionSerializable>;
    }
  ): Promise<Hex> => {
    if (!args?.serializer) {
      return signTransaction(transaction, {
        serializer: serializeTransaction,
      });
    }
    const serialized = args.serializer(transaction);
    const hash = keccak256(serialized as Address);
    const hashBytes = hexToBytes(hash);
    const signature = await actor.signWithEvmWallet(hashBytes);

    // 0xプレフィックスを削除
    const sigHex = signature.startsWith('0x') ? signature.slice(2) : signature;
    
    // 署名は65バイト (130文字) である必要がある
    if (sigHex.length !== 130) {
      throw new Error(`Invalid signature length: ${sigHex.length}, expected 130`);
    }
    
    const r = '0x' + sigHex.slice(0, 64);
    const s = '0x' + sigHex.slice(64, 128);
    let v = parseInt(sigHex.slice(128, 130), 16);
    
    // Ethereumの署名では、v値は27または28である必要がある
    // recovery IDが0または1の場合、27を加算する
    if (v < 27) {
      v += 27;
    }
    
    console.log('Parsed signature - r:', r, 's:', s, 'v:', v);
    
    const sig: Signature = {
      r: r as Hex,
      s: s as Hex,
      v: BigInt(v),
    };
    
    return args.serializer(transaction, sig);
  };

  const signTypedData = async <
    typedData extends TypedData | Record<string, unknown>,
    primaryType extends keyof typedData | 'EIP712Domain' = keyof typedData,
  >(
    _typedData: TypedDataDefinition<typedData, primaryType>,
  ): Promise<Hex> => {
    throw new Error('Typed data signing is not supported yet for ICP wallet.');
  };

  return toAccount({
    address: evmAddress,
    signMessage,
    signTransaction,
    signTypedData,
  });
};

export interface CreateIcpWalletOptions {
  authClient: AuthClient;
  chain: Chain;
  transport?: HttpTransport | undefined;
}

// export type IcpWalletClient<TChain extends Chain = Chain> = WalletClient<HttpTransport, TChain, LocalAccount>;
export type IcpWalletClient = WalletClient<HttpTransport, Chain, LocalAccount, RpcSchema>;

export async function createIcpWalletClient(
  options: CreateIcpWalletOptions,
): Promise<IcpWalletClient> {
  if (!(await options.authClient.isAuthenticated())) {
    throw new Error('Auth client must be authenticated before creating wallet client.');
  }

  const account = await toIcpAccount(options.authClient);
  const walletClient = createWalletClient({
    account,
    chain: options.chain,
    transport: options.transport ?? http(), // transportがundefinedまたは未指定の場合はダミー値を使用
  });

  return walletClient;
}
