import { create } from "zustand";
import * as SecureStore from "expo-secure-store";

import { registerTokenReader } from "@/services/api";

const ACCESS_TOKEN_KEY = "aperto.access_token";
const REFRESH_TOKEN_KEY = "aperto.refresh_token";

type AuthState = {
  accessToken: string | null;
  refreshToken: string | null;
  hydrated: boolean;
  signIn: (tokens: { accessToken: string; refreshToken: string }) => Promise<void>;
  signOut: () => Promise<void>;
  hydrate: () => Promise<void>;
};

/**
 * Tokens live in SecureStore (Keychain / Android Keystore), never in
 * AsyncStorage — AsyncStorage is plain files, readable on a rooted device and
 * swept into backups. `hydrated` exists so the router can hold the splash
 * screen until we know whether there is a session, instead of flashing the
 * signed-out screen and then replacing it.
 */
export const useAuthStore = create<AuthState>((set, get) => ({
  accessToken: null,
  refreshToken: null,
  hydrated: false,

  hydrate: async () => {
    const [accessToken, refreshToken] = await Promise.all([
      SecureStore.getItemAsync(ACCESS_TOKEN_KEY),
      SecureStore.getItemAsync(REFRESH_TOKEN_KEY),
    ]);
    set({ accessToken, refreshToken, hydrated: true });
  },

  signIn: async ({ accessToken, refreshToken }) => {
    await Promise.all([
      SecureStore.setItemAsync(ACCESS_TOKEN_KEY, accessToken),
      SecureStore.setItemAsync(REFRESH_TOKEN_KEY, refreshToken),
    ]);
    set({ accessToken, refreshToken });
  },

  signOut: async () => {
    await Promise.all([
      SecureStore.deleteItemAsync(ACCESS_TOKEN_KEY),
      SecureStore.deleteItemAsync(REFRESH_TOKEN_KEY),
    ]);
    set({ accessToken: null, refreshToken: null });
  },
}));

registerTokenReader(() => useAuthStore.getState().accessToken);

export { ACCESS_TOKEN_KEY, REFRESH_TOKEN_KEY };
