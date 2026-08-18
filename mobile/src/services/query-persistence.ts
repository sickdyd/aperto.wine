import AsyncStorage from "@react-native-async-storage/async-storage";
import { defaultShouldDehydrateQuery, type Query } from "@tanstack/react-query";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import type { PersistQueryClientProviderProps } from "@tanstack/react-query-persist-client";

/**
 * Opting a query into the on-disk cache.
 *
 * Restaurant wifi is unreliable, and a diner who has already loaded a wine list
 * should keep seeing it through a dead spot — so a persisted cache is a real
 * product requirement, not a nicety. But the store behind it is AsyncStorage:
 * plain unencrypted files, readable on a rooted or jailbroken device and swept
 * into iCloud/Google device backups. Tokens already avoid it for exactly that
 * reason (see stores/auth-store.ts, which keeps them in SecureStore).
 *
 * TanStack Query's own default is to dehydrate *every* successful query. That
 * default is opt-out, and opt-out is the dangerous shape here: the roadmap is
 * diner accounts with bonuses, discounts and order history, and the moment
 * those queries exist they would land in plaintext silently, with nobody having
 * decided they should. So this is default-deny — a query is persisted only if
 * it says so itself:
 *
 *     useQuery({
 *       queryKey: ["menu", tableToken],
 *       queryFn: fetchMenu,
 *       meta: { persist: true }, // public wine list; safe in a plaintext backup
 *     })
 *
 * The flag lives on the query rather than in a list here, and that placement is
 * the whole point. A list keyed on `["menu", …]` would grant that namespace
 * once and forever: the day a menu becomes diner-specific — "your 10% off", a
 * price adjusted for a returning regular — the payload changes, the key does
 * not, and the list cannot see it happen. Nobody edits this file, so nobody
 * re-decides. Written on the query, `persist: true` sits three lines from the
 * `queryFn` whose response just gained a discount, in the same object, in the
 * same diff, in front of the same reviewer.
 *
 * The question to ask before writing it: **would we be relaxed about this
 * sitting in an unencrypted backup of a phone we do not control?** A
 * restaurant's published wine list is already public — it is what the QR code
 * hands to anyone who scans it. Anything that varies by *who is asking* is not,
 * even when it looks like the same screen: a personalised menu, a bonus
 * balance, a discount, an order history, a saved address. Those belong in
 * memory for the session, or in SecureStore if they genuinely have to outlive
 * the process.
 *
 * If a persisted query later becomes diner-specific, **remove the flag** — that
 * is the change, and it is a one-line one.
 *
 * One library caveat, for whenever the first prefetch lands: `meta` round-trips
 * through hydration, and `prefetchQuery`/`ensureQueryData` reuse a cached query
 * without refreshing it from the call site the way `useQuery` does. Nobody
 * gains anything by that today — rewriting the cache file needs the same device
 * access that would let you read it.
 */
declare module "@tanstack/react-query" {
  interface Register {
    queryMeta: {
      /**
       * Persist this query to unencrypted on-device storage. Only ever `true`,
       * and only for data that is already public — read the note above first.
       */
      persist?: true;
    };
  }
}

const warned = new Set<string>();

/**
 * Names only the key *root*, never the rest of the key: the root identifies the
 * query well enough to act on, and the remaining segments are request
 * parameters that have no business being printed. Without this the gate would
 * be silent, and a wine list quietly failing to survive a dead spot looks
 * exactly like a wine list that was never cached.
 *
 * A non-string root is not printed at all — an object root could carry those
 * same parameters — so every such query shares one warning. That is a loss of
 * diagnostic precision only: the gate decides on the flag, never on the shape
 * of the key.
 */
function warnDenied(query: Query): void {
  const root = typeof query.queryKey[0] === "string" ? query.queryKey[0] : "(non-string key)";
  if (!__DEV__ || warned.has(root)) return;
  warned.add(root);

  console.warn(
    `[query-persistence] Not persisting queries keyed on "${root}". The cache on ` +
      `disk is unencrypted AsyncStorage, so a query opts in explicitly or not at ` +
      `all. If this data is already public and should survive a dead spot, add ` +
      `\`meta: { persist: true }\` to the query — and read the note in ` +
      `src/services/query-persistence.ts first, particularly if the response ` +
      `varies by which diner is asking.`,
  );
}

/**
 * Deliberately composed with `defaultShouldDehydrateQuery` rather than
 * replacing it: overriding this option drops TanStack's own success-only rule,
 * which would otherwise start writing failed and pending queries to disk as a
 * side effect of adding a gate.
 */
export function shouldDehydrateQuery(query: Query): boolean {
  if (!defaultShouldDehydrateQuery(query)) return false;
  if (query.meta?.persist === true) return true;

  warnDenied(query);
  return false;
}

/**
 * No mutation is ever persisted, and there is no opt-in for them.
 *
 * TanStack's default keeps *paused* mutations so they can replay when
 * connectivity returns. In this app a mutation is an order, and the server is
 * explicit that a placement is re-checked and re-priced under a lock at the
 * moment it happens — an order replayed off disk hours later would be a
 * different order than the diner built, against a cellar that has moved. The
 * paused payload would also be sitting in plaintext the whole time it waited.
 */
export function shouldDehydrateMutation(): boolean {
  return false;
}

const persister = createAsyncStoragePersister({ storage: AsyncStorage });

/** The exact object handed to `PersistQueryClientProvider`. */
export const persistOptions: PersistQueryClientProviderProps["persistOptions"] = {
  persister,
  dehydrateOptions: { shouldDehydrateQuery, shouldDehydrateMutation },
};
