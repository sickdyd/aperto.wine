import Constants from "expo-constants";

/**
 * Everything the app needs to know about which backend it is talking to.
 *
 * EXPO_PUBLIC_* variables are inlined into the bundle at build time, so they are
 * public by definition — never put a secret here. The API base URL and the
 * Sentry DSN are both fine; both are visible to anyone who unzips the .ipa.
 */

const DEFAULT_DEV_API = "http://localhost:4010/api/v1";

function readApiUrl(): string {
  const url = process.env.EXPO_PUBLIC_API_URL ?? DEFAULT_DEV_API;

  // A trailing slash turns every axios path into a double slash, which Rails
  // routes as a 404 with no useful error. Cheaper to normalise once here than
  // to debug it per endpoint.
  return url.replace(/\/+$/, "");
}

export const config = {
  apiUrl: readApiUrl(),
  variant: (Constants.expoConfig?.extra?.variant as string) ?? "development",
  sentry: {
    dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
    environment: process.env.EXPO_PUBLIC_SENTRY_ENVIRONMENT ?? "development",
  },
} as const;

export const isProduction = config.variant === "production";
