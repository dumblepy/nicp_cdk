import { useMemo } from "react";
import { HttpAgent, type Identity } from "@icp-sdk/core/agent";
import { getCanisterEnv } from "@icp-sdk/core/agent/canister-env";
import { createActor, type Backend } from "../backend/api/backend";

interface VetkeyCanisterEnv {
  readonly "PUBLIC_CANISTER_ID:backend": string;
}

function devAgentHost(): string {
  if (typeof window === "undefined") {
    return "";
  }
  return `${window.location.origin}/api`;
}

export function useVetkeyBackend(identity: Identity | null): Backend | null {
  return useMemo(() => {
    if (!identity || typeof window === "undefined") {
      return null;
    }
    const env = getCanisterEnv<VetkeyCanisterEnv>();
    const canisterId = env["PUBLIC_CANISTER_ID:backend"];
    const agent = HttpAgent.createSync({
      identity,
      host: import.meta.env.DEV ? devAgentHost() : undefined,
      shouldFetchRootKey: import.meta.env.DEV,
      rootKey: import.meta.env.DEV ? undefined : env.IC_ROOT_KEY,
    });
    return createActor(canisterId, { agent });
  }, [identity]);
}
