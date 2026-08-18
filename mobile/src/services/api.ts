import axios, { AxiosError, type AxiosInstance } from "axios";

import { config } from "@/constants/config";
import i18n from "@/i18n";
import { apiErrorSchema } from "@/types/api";

/**
 * NOTE: aperto.wine has no api/v1 namespace yet — the Rails app is entirely
 * HTML controllers with session-cookie auth. This client is written against the
 * contract jeero's Api::V1 established (Bearer access token, X-Locale, the
 * { error: { code, message } } envelope) so the server can be built to meet it.
 * Until it exists every request here fails, loudly and legibly, at the
 * interceptor below.
 */

export type NormalisedError = {
  code: string;
  message: string;
  status?: number;
};

let getAccessToken: () => string | null = () => null;

/** Lets the auth store hand the client a token reader without a circular import. */
export function registerTokenReader(reader: () => string | null): void {
  getAccessToken = reader;
}

export function createApiClient(baseURL: string = config.apiUrl): AxiosInstance {
  const client = axios.create({
    baseURL,
    timeout: 15_000,
    headers: { Accept: "application/json" },
  });

  client.interceptors.request.use((request) => {
    const token = getAccessToken();
    if (token) request.headers.Authorization = `Bearer ${token}`;

    // The server negotiates locale from this rather than from Accept-Language,
    // so an Italian phone reading the list in English gets English copy from
    // both sides instead of an English shell around Italian server strings.
    request.headers["X-Locale"] = i18n.language;
    return request;
  });

  client.interceptors.response.use(
    (response) => response,
    (error: AxiosError) => Promise.reject(normaliseError(error)),
  );

  return client;
}

/**
 * Collapses every failure mode into one shape the UI can branch on. Axios
 * distinguishes "no response" from "error response" and React components should
 * not have to.
 */
export function normaliseError(error: AxiosError): NormalisedError {
  if (!error.response) {
    return { code: "network_error", message: i18n.t("errors.network") };
  }

  const status = error.response.status;
  const parsed = apiErrorSchema.safeParse(error.response.data);

  if (parsed.success) {
    return { ...parsed.data.error, status };
  }

  // A response that isn't our envelope means something upstream answered — a
  // proxy, a maintenance page, a 502 from the load balancer. Report the status
  // rather than pretending to know the cause.
  return {
    code: status === 404 ? "not_found" : "unexpected_response",
    message: status === 404 ? i18n.t("errors.notFound") : i18n.t("errors.server"),
    status,
  };
}

// Built on first use rather than at import. A module-level client makes the
// whole module unimportable wherever axios is stubbed, and drags client
// construction into any file that only wants `normaliseError`.
let client: AxiosInstance | null = null;

export function api(): AxiosInstance {
  return (client ??= createApiClient());
}

/** Test seam: drops the memoised client so the next api() rebuilds it. */
export function resetApiClient(): void {
  client = null;
}
