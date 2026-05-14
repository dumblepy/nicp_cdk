import { useState } from "react";
import type { Backend } from "../backend/api/backend";
import {
  PRIVATE_KV_DOMAIN_SEP,
  bytesToHex,
  decryptCiphertextWithVetkey,
  encryptPlaintextWithVetkey,
  generateTransportKeyPair,
  hexToBytes,
} from "../lib/vetkeyCrypto";

function utf8Bytes(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

function utf8String(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

/** Agent の拒否理由（rejectMessage / toErrorMessage）を可能な限り表示する */
function formatIcpAgentError(err: unknown): string {
  if (!(err instanceof Error)) {
    return String(err);
  }
  const cause = (err as Error & { cause?: unknown }).cause as
    | { code?: { toErrorMessage?: () => string; rejectMessage?: string } }
    | undefined;
  const code = cause?.code;
  if (code && typeof code.toErrorMessage === "function") {
    return code.toErrorMessage();
  }
  if (code && typeof code.rejectMessage === "string" && code.rejectMessage.length > 0) {
    return code.rejectMessage;
  }
  return err.message;
}

export interface PrivateKvRoundtripProps {
  backend: Backend | null;
}

export function PrivateKvRoundtrip({ backend }: PrivateKvRoundtripProps) {
  const [keyVersion, setKeyVersion] = useState("1");
  const [plaintext, setPlaintext] = useState(
    "user secret payload for private kv",
  );
  const [busy, setBusy] = useState(false);
  const [log, setLog] = useState<string[]>([]);
  const [decrypted, setDecrypted] = useState<string | null>(null);
  const [lastCiphertextHex, setLastCiphertextHex] = useState<string | null>(
    null,
  );

  const pushLog = (line: string) => {
    setLog((prev) => [...prev, line]);
  };

  const runRoundtrip = async () => {
    if (!backend) {
      pushLog("バックエンドがありません。Internet Identity でログインしてください。");
      return;
    }
    const kv = BigInt(keyVersion.trim() || "0");
    if (kv < 0n) {
      pushLog("key version は 0 以上の整数にしてください。");
      return;
    }

    setBusy(true);
    setLog([]);
    setDecrypted(null);
    setLastCiphertextHex(null);

    try {
      const { transportSecretHex, transportPublicHex } =
        generateTransportKeyPair();
      pushLog("transport 鍵ペアを生成しました。");
      console.log("generateTransportKeyPair", {
        transportPublicHex,
        transportPublicHexLower: transportPublicHex.trim().toLowerCase(),
      });      

      const derive = await backend.derivePrivateKvKey(
        transportPublicHex,
        kv,
      );
      console.log("derivePrivateKvKey", {
        derive,
        owner: derive.owner.toString(),
        contextLabel: derive.context_label,
      });
      const ownerStr = derive.owner.toString();
      const expectedCtx = `${PRIVATE_KV_DOMAIN_SEP}|owner=${ownerStr}`;
      if (derive.context_label !== expectedCtx) {
        throw new Error(
          `context_label が期待と異なります: ${derive.context_label}`,
        );
      }
      pushLog(`derivePrivateKvKey OK（context: ${derive.context_label}）`);

      const pt = utf8Bytes(plaintext);
      const ciphertext = await encryptPlaintextWithVetkey(
        transportSecretHex,
        derive.encrypted_key_hex,
        pt,
        PRIVATE_KV_DOMAIN_SEP,
      );
      console.log("=== encryptPlaintextWithVetkey ===", {
        transportSecretHex,
        encryptedKeyHex: derive.encrypted_key_hex,
        plaintextHex: bytesToHex(pt),
        domainSep: PRIVATE_KV_DOMAIN_SEP,
      });
      console.log("ciphertext", {
        ciphertext,
        ciphertextHex: bytesToHex(ciphertext),
      });
      const localCipherHex = bytesToHex(ciphertext);
      console.log("localCipherHex", localCipherHex);
      setLastCiphertextHex(localCipherHex);
      pushLog("クライアント側で vetKey 素材を用いて暗号化しました。");

      await backend.storePrivateKv(ciphertext, kv);
      pushLog("storePrivateKv を呼び出しました。");

      const fetched = await backend.fetchPrivateKv();
      console.log("=== fetchPrivateKv ===");
      console.log("fetched", {
        fetched,
        fetchedCiphertextHex: fetched.ciphertext_hex,
        fetchedCiphertextHexLower: fetched.ciphertext_hex.trim().toLowerCase(),
      });
      const fetchedLower = fetched.ciphertext_hex.trim().toLowerCase();
      const localLower = localCipherHex.toLowerCase();
      if (fetchedLower !== localLower) {
        throw new Error(
          "fetch した ciphertext がローカル暗号文と一致しません。",
        );
      }
      pushLog("fetchPrivateKv の ciphertext が一致することを確認しました。");

      const decryptedBytes = await decryptCiphertextWithVetkey(
        transportSecretHex,
        derive.encrypted_key_hex,
        hexToBytes(fetched.ciphertext_hex),
        PRIVATE_KV_DOMAIN_SEP,
      );
      console.log("=== decryptCiphertextWithVetkey ===", {
        decryptedBytes,
        decryptedBytesHex: bytesToHex(decryptedBytes),
        decryptedBytesUtf8: utf8String(decryptedBytes),
      });
      const out = utf8String(decryptedBytes);
      setDecrypted(out);
      if (out !== plaintext) {
        throw new Error("復号結果が入力平文と一致しません。");
      }
      pushLog("復号に成功し、平文が一致しました。");
    } catch (e) {
      pushLog(`エラー: ${formatIcpAgentError(e)}`);
      console.error(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="section">
      <h2 className="sectionTitle">Private KV（vetKey 暗号化）</h2>
      <p className="sectionLead">
        テスト{" "}
        <code className="inlineCode">Private KV roundtrip</code>{" "}
        と同じ手順です。caller ごとのプリンシパルに紐づく KV に、transport
        鍵で保護された vetKey から導いた素材で暗号化したデータを保存し、取り出して復号します。
      </p>

      <label className="fieldLabel" htmlFor="kv-version">
        key version（nat64）
      </label>
      <input
        id="kv-version"
        className="input fullWidth"
        type="text"
        inputMode="numeric"
        value={keyVersion}
        onInput={(e) => setKeyVersion((e.target as HTMLInputElement).value)}
        disabled={busy || !backend}
      />

      <label className="fieldLabel" htmlFor="kv-plain">
        平文
      </label>
      <textarea
        id="kv-plain"
        className="textarea"
        rows={4}
        value={plaintext}
        onInput={(e) =>
          setPlaintext((e.target as HTMLTextAreaElement).value)
        }
        disabled={busy || !backend}
      />

      <div className="row">
        <button
          type="button"
          className="button"
          onClick={() => void runRoundtrip()}
          disabled={busy || !backend}
        >
          {busy ? "実行中…" : "暗号化 → 保存 → 取得 → 復号"}
        </button>
      </div>

      {lastCiphertextHex !== null && (
        <details className="details">
          <summary>暗号文（hex）</summary>
          <pre className="pre mono">{lastCiphertextHex}</pre>
        </details>
      )}

      {decrypted !== null && (
        <p className="success">
          <strong>復号結果:</strong> {decrypted}
        </p>
      )}

      {log.length > 0 && (
        <details className="details" open>
          <summary>ログ</summary>
          <ol className="logList">
            {log.map((line, i) => (
              <li key={i}>{line}</li>
            ))}
          </ol>
        </details>
      )}
    </section>
  );
}
