import { describe, test, expect, beforeAll } from 'vitest';
import { verifyMessage, type Hex, hashMessage, hexToBytes } from 'viem';
import { createTestActor } from './testHelper';
import type { _SERVICE } from '../../../declarations/t_ecdsa_backend/t_ecdsa_backend.did';

/**
 * Ethereum署名のテスト
 * 
 * このテストは以下のフローを実行します:
 * 1. ICPキャニスターからEthereumウォレットアドレスを取得
 * 2. メッセージに対してキャニスターで署名を実行
 * 3. viemのverifyMessage関数で署名を検証
 */
describe('Ethereum署名とviem検証のテスト', () => {
  let actor: _SERVICE;
  
  beforeAll(async () => {
    // ICPキャニスターへの接続を確立
    actor = await createTestActor();
    await actor.getNewPublicKey();
  });

  test('Ethereumアドレスを取得できること', async () => {
    const address = await actor.getEvmAddress();
    
    // Ethereumアドレスは0xで始まる42文字（0x + 40桁の16進数）
    expect(address).toMatch(/^0x[a-fA-F0-9]{40}$/);
    
    console.log('取得したEthereumアドレス:', address);
  });

  test('signWithEthereum: メッセージをハッシュ化してから署名・検証できること', async () => {
    const message = 'Hello, EIP-191!';
    
    // Step 1: Ethereumアドレスを取得
    const ethereumAddress = await actor.getEvmAddress();
    expect(ethereumAddress).toMatch(/^0x[a-fA-F0-9]{40}$/);
    console.log('Ethereumアドレス:', ethereumAddress);
    
    // Step 2: メッセージをEIP-191フォーマットでハッシュ化
    // EIP-191: "\x19Ethereum Signed Message:\n" + len(message) + message
    const messageHash = hashMessage(message);
    expect(messageHash).toMatch(/^0x[a-fA-F0-9]{64}$/); // 32バイトのハッシュ
    console.log('メッセージハッシュ (EIP-191):', messageHash);
    
    // Step 3: ハッシュに対してICPキャニスターで署名を実行
    // signWithEthereumは内部でEIP-191ハッシュ化を行うので、元のメッセージで署名
    const signature = await actor.signWithEthereum(message);
    expect(signature).toBeTruthy();
    expect(signature).toMatch(/^0x[a-fA-F0-9]{130}$/);
    console.log('署名:', signature);
    
    // Step 4: viemのverifyMessage関数で署名を検証
    // verifyMessageは内部でEIP-191フォーマットに変換して検証する
    const isValid = await verifyMessage({
      address: ethereumAddress as Hex,
      message: message,
      signature: signature as Hex,
    });
    
    console.log('署名検証結果:', isValid);
    expect(isValid).toBe(true);
  });

  test('signWithEthereum: 複数のメッセージでハッシュ化署名・検証できること', async () => {
    const messages = [
      'EIP-191 test message 1',
      'EIP-191 テストメッセージ 2',
      'EIP-191 test with emoji 🔐',
    ];
    
    const ethereumAddress = await actor.getEvmAddress();
    
    for (const message of messages) {
      // メッセージをEIP-191フォーマットでハッシュ化
      const messageHash = hashMessage(message);
      console.log(`メッセージ "${message}" のハッシュ:`, messageHash);
      
      // メッセージに署名（signWithEthereumが内部でEIP-191ハッシュ化を行う）
      const signature = await actor.signWithEthereum(message);
      
      // verifyMessageで検証（内部でEIP-191フォーマットに変換）
      const isValid = await verifyMessage({
        address: ethereumAddress as Hex,
        message: message,
        signature: signature as Hex,
      });
      
      expect(isValid).toBe(true);
      console.log(`メッセージ "${message}" の検証: ${isValid}`);
    }
  });

  test('signWithEthereum: 異なるメッセージの署名は検証に失敗すること', async () => {
    const message1 = 'Original message';
    const message2 = 'Different message';
    
    const ethereumAddress = await actor.getEvmAddress();
    
    // message1のハッシュ値を確認
    const hash1 = hashMessage(message1);
    const hash2 = hashMessage(message2);
    console.log('message1のハッシュ:', hash1);
    console.log('message2のハッシュ:', hash2);
    
    // message1に署名
    const signature = await actor.signWithEthereum(message1);
    
    // message2で検証を試みる（失敗するはず）
    const isValid = await verifyMessage({
      address: ethereumAddress as Hex,
      message: message2,
      signature: signature as Hex,
    });
    
    expect(isValid).toBe(false);
    console.log('異なるメッセージでの検証結果:', isValid);
  });

  test('signWithEvmWallet: ハッシュ化されたデータに直接署名して検証できること', async () => {
    const message = 'Hello, signWithEvmWallet!';
    
    // Step 1: Ethereumアドレスを取得
    const ethereumAddress = await actor.getEvmAddress();
    expect(ethereumAddress).toMatch(/^0x[a-fA-F0-9]{40}$/);
    console.log('Ethereumアドレス:', ethereumAddress);
    
    // Step 2: メッセージをEIP-191フォーマットでハッシュ化
    const messageHash = hashMessage(message);
    expect(messageHash).toMatch(/^0x[a-fA-F0-9]{64}$/);
    console.log('メッセージハッシュ:', messageHash);
    
    // Step 3: ハッシュをバイト配列に変換してsignWithEvmWalletで署名
    const hashBytes = hexToBytes(messageHash as Hex);
    const signature = await actor.signWithEvmWallet(hashBytes);
    expect(signature).toBeTruthy();
    expect(signature).toMatch(/^0x[a-fA-F0-9]{130}$/);
    console.log('署名:', signature);
    
    // Step 4: verifyMessageのrawオプションでハッシュを直接検証
    const isValid = await verifyMessage({
      address: ethereumAddress as Hex,
      message: message,
      signature: signature as Hex,
    });
    
    console.log('署名検証結果:', isValid);
    expect(isValid).toBe(true);
  });

  test('signWithEvmWallet: 複数のメッセージでハッシュ化データの署名・検証', async () => {
    const messages = [
      'signWithEvmWallet test 1',
      'signWithEvmWallet テスト 2',
      'signWithEvmWallet with emoji 🎉',
    ];
    
    const ethereumAddress = await actor.getEvmAddress();
    
    for (const message of messages) {
      // メッセージをハッシュ化
      const messageHash = hashMessage(message);
      console.log(`メッセージ "${message}" のハッシュ:`, messageHash);
      
      // ハッシュをバイト配列に変換して署名
      const hashBytes = hexToBytes(messageHash as Hex);
      const signature = await actor.signWithEvmWallet(hashBytes);
      
      // rawオプションで検証
      const isValid = await verifyMessage({
        address: ethereumAddress as Hex,
        message: message,
        signature: signature as Hex,
      });
      
      expect(isValid).toBe(true);
      console.log(`メッセージ "${message}" の検証: ${isValid}`);
    }
  });

  test('signWithEvmWallet: 異なるハッシュでの検証は失敗すること', async () => {
    const message1 = 'First message';
    const message2 = 'Second message';
    
    const ethereumAddress = await actor.getEvmAddress();
    
    // message1のハッシュに署名
    const hash1 = hashMessage(message1);
    const hashBytes1 = hexToBytes(hash1 as Hex);
    const signature = await actor.signWithEvmWallet(hashBytes1);
    
    // message2のハッシュで検証を試みる（失敗するはず）
    const hash2 = hashMessage(message2);
    console.log('署名したハッシュ:', hash1);
    console.log('検証に使うハッシュ:', hash2);
    
    const isValid = await verifyMessage({
      address: ethereumAddress as Hex,
      message: message2,
      signature: signature as Hex,
    });
    
    expect(isValid).toBe(false);
    console.log('異なるハッシュでの検証結果:', isValid);
  });
});

