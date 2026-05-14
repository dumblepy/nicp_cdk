import { useIcpAuth } from "./hooks/useIcpAuth";
import { useVetkeyBackend } from "./hooks/useVetkeyBackend";
import { PrivateKvRoundtrip } from "./components/PrivateKvRoundtrip";
import "./App.css";

export default function App() {
  const {
    isAuthenticated,
    isLoading,
    principalText,
    identity,
    identityProviderUrl,
    login,
    logout,
  } = useIcpAuth();

  const backend = useVetkeyBackend(identity);

  const handleAuth = async () => {
    if (isAuthenticated) {
      await logout();
      return;
    }
    await login();
  };

  return (
    <main className="page">
      <article className="panel wide">
        <div className="brand" aria-label="ICP plus Vite">
          <img src="/icp.svg" alt="ICP logo" className="brand-icp" />
          <span className="plus">+</span>
          <img src="/vite.svg" alt="Vite logo" className="brand-vite" />
        </div>
        <h1 className="title">vetKey サンプル</h1>
        <p className="subtitle">
          Internet Identity で認証し、Private KV に vetKey 由来の鍵素材で暗号化したテキストを保存・復号します。
        </p>

        <section className="section">
          <h2 className="sectionTitle">認証</h2>
          <p className="status">
            Identity プロバイダ:{" "}
            <span className="mono">{identityProviderUrl}</span>
          </p>
          <div className="row">
            <button
              type="button"
              className="button"
              onClick={() => void handleAuth()}
              disabled={isLoading}
            >
              {isAuthenticated
                ? "ログアウト"
                : "Internet Identity でログイン"}
            </button>
          </div>
          <p className="status">
            状態:{" "}
            {isLoading
              ? "確認中…"
              : isAuthenticated
                ? "ログイン済み"
                : "未ログイン"}
          </p>
          {isAuthenticated && principalText && (
            <p className="principal">
              <strong>Principal:</strong>{" "}
              <span className="mono">{principalText}</span>
            </p>
          )}
          {isAuthenticated && (
            <p className="status">
              バックエンド接続:{" "}
              {backend ? "準備完了" : "ic_env クッキーまたは環境を確認"}
            </p>
          )}
        </section>

        <PrivateKvRoundtrip backend={backend} />
      </article>
    </main>
  );
}
