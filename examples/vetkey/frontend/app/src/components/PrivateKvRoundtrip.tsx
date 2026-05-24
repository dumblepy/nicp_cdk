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

function requireTrimmedField(value: string, fieldName: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error(`${fieldName} がありません。`);
  }
  return trimmed;
}

export interface PrivateKvRoundtripProps {
  backend: Backend | null;
}

type BusyAction = "encrypt" | "decrypt" | null;

export function PrivateKvRoundtrip({ backend }: PrivateKvRoundtripProps) {
  const [keyVersion, setKeyVersion] = useState("1");
  const [plaintext, setPlaintext] = useState(
    "user secret payload for private kv",
  );
  const [decryptTransportSecretHex, setDecryptTransportSecretHex] =
    useState("");
  const [decryptEncryptedKeyHex, setDecryptEncryptedKeyHex] = useState("");
  const [decryptCiphertextHex, setDecryptCiphertextHex] = useState("");
  const [decryptKeyVersion, setDecryptKeyVersion] = useState("");
  const [busyAction, setBusyAction] = useState<BusyAction>(null);
  const [log, setLog] = useState<string[]>([]);
  const [decrypted, setDecrypted] = useState<string | null>(null);
  const [lastCiphertextHex, setLastCiphertextHex] = useState<string | null>(
    null,
  );

  const encryptBusy = busyAction === "encrypt";
  const decryptBusy = busyAction === "decrypt";
  const isBusy = busyAction !== null;

  const pushLog = (line: string) => {
    setLog((prev) => [...prev, line]);
  };

  const runEncrypt = async () => {
    if (!backend) {
      pushLog("暗号化: バックエンドがありません。Internet Identity でログインしてください。");
      return;
    }

    const normalizedKeyVersion = keyVersion.trim();
    if (normalizedKeyVersion.length === 0) {
      pushLog("暗号化: key version は 0 以上の整数にしてください。");
      return;
    }

    let kv: bigint;
    try {
      kv = BigInt(normalizedKeyVersion);
    } catch {
      pushLog("暗号化: key version は 0 以上の整数にしてください。");
      return;
    }
    if (kv < 0n) {
      pushLog("暗号化: key version は 0 以上の整数にしてください。");
      return;
    }

    setBusyAction("encrypt");
    setLog([]);
    setDecrypted(null);
    setLastCiphertextHex(null);

    try {
      const { transportSecretHex, transportPublicHex } =
        generateTransportKeyPair();
      pushLog("暗号化: transport 鍵ペアを生成しました。");

      const derive = await backend.derivePrivateKvKey(
        transportPublicHex,
        kv,
      );
      const ownerStr = derive.owner.toString();
      const expectedCtx = `${PRIVATE_KV_DOMAIN_SEP}|owner=${ownerStr}`;
      if (derive.context_label !== expectedCtx) {
        throw new Error(
          `context_label が期待と異なります: ${derive.context_label}`,
        );
      }
      pushLog(`暗号化: derivePrivateKvKey OK（context: ${derive.context_label}）`);

      const plaintextBytes = utf8Bytes(plaintext);
      const ciphertextBytes = await encryptPlaintextWithVetkey(
        transportSecretHex,
        derive.encrypted_key_hex,
        plaintextBytes,
        PRIVATE_KV_DOMAIN_SEP,
      );
      const localCipherHex = bytesToHex(ciphertextBytes);
      pushLog("暗号化: クライアント側で vetKey 素材を用いて暗号化しました。");

      await backend.storePrivateKv(ciphertextBytes, kv);
      pushLog("暗号化: storePrivateKv を呼び出しました。");

      const fetched = await backend.fetchPrivateKv();
      const fetchedCipherHex = fetched.ciphertext_hex.trim();
      if (fetchedCipherHex.toLowerCase() !== localCipherHex.toLowerCase()) {
        throw new Error(
          "fetch した ciphertext がローカル暗号文と一致しません。",
        );
      }
      pushLog("暗号化: fetchPrivateKv の ciphertext が一致することを確認しました。");

      setLastCiphertextHex(fetchedCipherHex);
      setDecryptTransportSecretHex(transportSecretHex);
      setDecryptEncryptedKeyHex(derive.encrypted_key_hex);
      setDecryptCiphertextHex(fetchedCipherHex);
      setDecryptKeyVersion(normalizedKeyVersion);
      pushLog("暗号化: 復号用の 4 つの入力欄へ反映しました。");
    } catch (e) {
      pushLog(`暗号化: エラー - ${formatIcpAgentError(e)}`);
      console.error(e);
    } finally {
      setBusyAction(null);
    }
  };

  const runDecrypt = async () => {
    if (!backend) {
      pushLog("復号: バックエンドがありません。Internet Identity でログインしてください。");
      return;
    }

    setBusyAction("decrypt");
    setLog([]);
    setDecrypted(null);

    try {
      const transportSecretHex = requireTrimmedField(
        decryptTransportSecretHex,
        "transportSecretHex",
      );
      const encryptedKeyHex = requireTrimmedField(
        decryptEncryptedKeyHex,
        "encryptedKeyHex",
      );
      const ciphertextHex = requireTrimmedField(
        decryptCiphertextHex,
        "ciphertextHex",
      );
      const keyVersion = decryptKeyVersion.trim();

      if (keyVersion.length > 0) {
        pushLog(`復号: keyVersion=${keyVersion} を確認しました。`);
      } else {
        pushLog("復号: keyVersion は未入力ですが、復号は継続します。");
      }

      const decryptedBytes = await decryptCiphertextWithVetkey(
        transportSecretHex,
        encryptedKeyHex,
        hexToBytes(ciphertextHex),
        PRIVATE_KV_DOMAIN_SEP,
      );
      const out = utf8String(decryptedBytes);
      setDecrypted(out);
      pushLog("復号: 復号に成功しました。");
    } catch (e) {
      pushLog(`復号: エラー - ${formatIcpAgentError(e)}`);
      console.error(e);
    } finally {
      setBusyAction(null);
    }
  };

  return (
    <section className="section">
      <h2 className="sectionTitle">Private KV（vetKey 暗号化）</h2>
      <p className="sectionLead">
        テスト{" "}
        <code className="inlineCode">Private KV roundtrip</code>{" "}
        と同じ手順です。暗号化と復号を分け、暗号化で作った入力値を UI
        上で確認・編集しながら復号できます。
      </p>

      <section className="subsection">
        <h3 className="sectionTitle">暗号化</h3>

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
          disabled={isBusy || !backend}
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
          disabled={isBusy || !backend}
        />

        <div className="row">
          <button
            type="button"
            className="button"
            onClick={() => void runEncrypt()}
            disabled={isBusy || !backend}
          >
            {encryptBusy ? "暗号化中…" : "暗号化して保存"}
          </button>
        </div>

        {lastCiphertextHex !== null && (
          <details className="details">
            <summary>暗号文（hex）</summary>
            <pre className="pre mono">{lastCiphertextHex}</pre>
          </details>
        )}
      </section>

      <section className="subsection">
        <h3 className="sectionTitle">復号</h3>
        <p className="sectionLead">
          暗号化後に自動入力される 4 つの値を、そのまま編集して復号できます。
        </p>

        <label className="fieldLabel" htmlFor="decrypt-transport-secret-hex">
          transportSecretHex
        </label>
        <input
          id="decrypt-transport-secret-hex"
          className="input fullWidth mono"
          type="text"
          value={decryptTransportSecretHex}
          onInput={(e) =>
            setDecryptTransportSecretHex(
              (e.target as HTMLInputElement).value,
            )
          }
          disabled={isBusy || !backend}
          spellCheck={false}
        />

        <label className="fieldLabel" htmlFor="decrypt-encrypted-key-hex">
          encryptedKeyHex
        </label>
        <input
          id="decrypt-encrypted-key-hex"
          className="input fullWidth mono"
          type="text"
          value={decryptEncryptedKeyHex}
          onInput={(e) =>
            setDecryptEncryptedKeyHex((e.target as HTMLInputElement).value)
          }
          disabled={isBusy || !backend}
          spellCheck={false}
        />

        <label className="fieldLabel" htmlFor="decrypt-ciphertext-hex">
          ciphertextHex
        </label>
        <input
          id="decrypt-ciphertext-hex"
          className="input fullWidth mono"
          type="text"
          value={decryptCiphertextHex}
          onInput={(e) =>
            setDecryptCiphertextHex((e.target as HTMLInputElement).value)
          }
          disabled={isBusy || !backend}
          spellCheck={false}
        />

        <label className="fieldLabel" htmlFor="decrypt-key-version">
          keyVersion
        </label>
        <input
          id="decrypt-key-version"
          className="input fullWidth mono"
          type="text"
          value={decryptKeyVersion}
          onInput={(e) =>
            setDecryptKeyVersion((e.target as HTMLInputElement).value)
          }
          disabled={isBusy || !backend}
          spellCheck={false}
        />

        <div className="row">
          <button
            type="button"
            className="button"
            onClick={() => void runDecrypt()}
            disabled={isBusy || !backend}
          >
            {decryptBusy ? "復号中…" : "入力値で復号"}
          </button>
        </div>

        {decrypted !== null && (
          <p className="success">
            <strong>復号結果:</strong> {decrypted}
          </p>
        )}
      </section>

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
