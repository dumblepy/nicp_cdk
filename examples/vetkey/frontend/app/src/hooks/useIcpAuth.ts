import { useCallback, useEffect, useRef, useState } from "react";
import { AuthClient } from "@icp-sdk/auth/client";
import type { Identity } from "@icp-sdk/core/agent";

/** ローカル開発用 Internet Identity（authorize フロー） */
const LOCAL_IDENTITY_PROVIDER = "http://id.ai.localhost:8000/#authorize";

function getIdentityProviderUrl(): string {
  const network = import.meta.env.VITE_IC_NETWORK ?? "local";
  if (network === "ic") {
    return "https://identity.ic0.app";
  }
  return LOCAL_IDENTITY_PROVIDER;
}

export interface UseIcpAuthResult {
  authClient: AuthClient | null;
  identityProviderUrl: string;
  isAuthenticated: boolean;
  isLoading: boolean;
  principalText: string | null;
  identity: Identity | null;
  login: () => Promise<boolean>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
}

export function useIcpAuth(): UseIcpAuthResult {
  const [authClient, setAuthClient] = useState<AuthClient | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [principalText, setPrincipalText] = useState<string | null>(null);
  const [identity, setIdentity] = useState<Identity | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const clientPromiseRef = useRef<Promise<AuthClient> | null>(null);

  const identityProviderUrl = getIdentityProviderUrl();

  const refreshSession = useCallback(async (client: AuthClient) => {
    try {
      const authenticated = await client.isAuthenticated();
      setIsAuthenticated(authenticated);
      if (authenticated) {
        const id = client.getIdentity();
        setIdentity(id);
        setPrincipalText(id.getPrincipal().toString());
      } else {
        setIdentity(null);
        setPrincipalText(null);
      }
    } catch (error) {
      console.error("Failed to refresh authentication session:", error);
      setIsAuthenticated(false);
      setIdentity(null);
      setPrincipalText(null);
    }
  }, []);

  const ensureAuthClient = useCallback(async (): Promise<AuthClient> => {
    if (authClient) {
      return authClient;
    }
    if (typeof window === "undefined") {
      throw new Error("Auth client is only available in the browser.");
    }
    if (!clientPromiseRef.current) {
      clientPromiseRef.current = AuthClient.create();
    }
    try {
      const client = await clientPromiseRef.current;
      setAuthClient((current) => current ?? client);
      return client;
    } catch (error) {
      clientPromiseRef.current = null;
      throw error;
    }
  }, [authClient]);

  useEffect(() => {
    if (typeof window === "undefined") {
      setIsLoading(false);
      return;
    }
    let cancelled = false;
    ensureAuthClient()
      .then((client) => {
        if (cancelled) {
          return;
        }
        return refreshSession(client);
      })
      .catch((error) => {
        if (!cancelled) {
          console.error("Failed to initialise auth client:", error);
        }
      })
      .finally(() => {
        if (!cancelled) {
          setIsLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [ensureAuthClient, refreshSession]);

  const login = useCallback(async () => {
    try {
      const client = await ensureAuthClient();
      return await new Promise<boolean>((resolve) => {
        client.login({
          identityProvider: identityProviderUrl,
          onSuccess: async () => {
            await refreshSession(client);
            resolve(true);
          },
          onError: (error) => {
            console.error("Login failed:", error);
            resolve(false);
          },
        });
      });
    } catch (error) {
      console.error("Failed to start login flow:", error);
      return false;
    }
  }, [ensureAuthClient, identityProviderUrl, refreshSession]);

  const logout = useCallback(async () => {
    try {
      const client = await ensureAuthClient();
      await client.logout();
      await refreshSession(client);
    } catch (error) {
      console.error("Logout failed:", error);
    }
  }, [ensureAuthClient, refreshSession]);

  const refresh = useCallback(async () => {
    try {
      const client = await ensureAuthClient();
      await refreshSession(client);
    } catch (error) {
      console.error("Failed to refresh authentication state:", error);
    }
  }, [ensureAuthClient, refreshSession]);

  return {
    authClient,
    identityProviderUrl,
    isAuthenticated,
    isLoading,
    principalText,
    identity,
    login,
    logout,
    refresh,
  };
}
