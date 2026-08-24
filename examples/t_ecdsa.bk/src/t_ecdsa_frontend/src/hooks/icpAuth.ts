import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { AuthClient } from '@icp-sdk/auth/client';
import {
  canisterId as INTERNET_IDENTITY_CANISTER_ID,
} from '../../../declarations/internet_identity';

const network = import.meta.env.VITE_DFX_NETWORK || 'local';
export const identityProvider =
  network === 'ic'
    ? 'https://identity.ic0.app'
    : `http://${INTERNET_IDENTITY_CANISTER_ID}.localhost:4943`;

export interface UseIcpAuthResult {
  authClient: AuthClient | null;
  identityProvider: string;
  isAuthenticated: boolean;
  isLoading: boolean;
  principal: string | null;
  login: () => Promise<boolean>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
}

export const useIcpAuth = (): UseIcpAuthResult => {
  const [authClient, setAuthClient] = useState<AuthClient | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [principal, setPrincipal] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const clientPromiseRef = useRef<Promise<AuthClient> | null>(null);

  const refreshSession = useCallback(async (client: AuthClient) => {
    try {
      const authenticated = await client.isAuthenticated();
      setIsAuthenticated(authenticated);
      if (authenticated) {
        const currentPrincipal = client.getIdentity().getPrincipal().toString();
        setPrincipal(currentPrincipal);
      } else {
        setPrincipal(null);
      }
    } catch (error) {
      console.error('Failed to refresh authentication session:', error);
      setIsAuthenticated(false);
      setPrincipal(null);
    }
  }, []);

  const ensureAuthClient = useCallback(async (): Promise<AuthClient> => {
    if (authClient) {
      return authClient;
    }

    if (typeof window === 'undefined') {
      throw new Error('Auth client is only available in the browser.');
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
    if (typeof window === 'undefined') {
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
          console.error('Failed to initialise auth client:', error);
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
          identityProvider,
          onSuccess: async () => {
            await refreshSession(client);
            resolve(true);
          },
          onError: (error) => {
            console.error('Login failed:', error);
            resolve(false);
          },
        });
      });
    } catch (error) {
      console.error('Failed to start login flow:', error);
      return false;
    }
  }, [ensureAuthClient, refreshSession]);

  const logout = useCallback(async () => {
    try {
      const client = await ensureAuthClient();
      await client.logout();
      await refreshSession(client);
    } catch (error) {
      console.error('Logout failed:', error);
    }
  }, [ensureAuthClient, refreshSession]);

  const refresh = useCallback(async () => {
    try {
      const client = await ensureAuthClient();
      await refreshSession(client);
    } catch (error) {
      console.error('Failed to refresh authentication state:', error);
    }
  }, [ensureAuthClient, refreshSession]);

  return {
    authClient,
    identityProvider,
    isAuthenticated,
    isLoading,
    principal,
    login,
    logout,
    refresh,
  };
};
