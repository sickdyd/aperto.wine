import AsyncStorage from "@react-native-async-storage/async-storage";
import { defaultShouldDehydrateQuery, type Query } from "@tanstack/react-query";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import type { PersistQueryClientProviderProps } from "@tanstack/react-query-persist-client";

/**
 * Which query key roots are allowed to survive on disk. Empty, deliberately.
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
 * decided they should. So the gate below is default-deny — a key root has to be
 * listed here before any of its data touches the disk.
 *
 * The list is empty rather than pre-seeded because the app has no queries yet,
 * and guessing at a key root nobody has written would be guessing. The first
 * query that wants to survive a dead spot adds its own root here, in the same
 * change, with the query in front of the reviewer — which is the decision this
 * whole file exists to force. Until then the cache is wired and does nothing,
 * which is the correct amount to persist when there is nothing safe to persist.
 *
 * The question to ask of a candidate root: would we be relaxed about this
 * appearing in an unencrypted backup of a phone we do not control? A
 * restaurant's published wine list is already public — it is what the QR code
 * hands to anyone who scans it, and it is the case the offline requirement is
 * about. Anything about a *person* is not: accounts, orders, bonuses,
 * discounts, contact details. Those belong in memory for the session, or in
 * SecureStore if they genuinely have to outlive the process.
 */
export const PERSISTED_QUERY_ROOTS: readonly string[] = [];

/**
 * The rule, separated from the list it is applied to, so the rule can be
 * exercised against a known root while the shipped list is still empty.
 *
 * Composed with `defaultShouldDehydrateQuery` rather than replacing it:
 * overriding this option drops TanStack's own success-only rule, which would
 * otherwise start writing failed and pending queries to disk as a side effect
 * of adding an allowlist.
 */
export function createPersistenceGate(
  roots: readonly string[],
): (query: Query) => boolean {
  // Denials are loud once and then quiet — a rejected key root is usually
  // rejected on every save, and this dedupe lasts for the life of the process.
  const warned = new Set<string>();

  return function shouldDehydrateQuery(query: Query): boolean {
    if (!defaultShouldDehydrateQuery(query)) return false;

    const root = query.queryKey[0];
    if (typeof root !== "string") return false;
    if (roots.includes(root)) return true;

    warnDenied(warned, root);
    return false;
  };
}

/**
 * Names only the key *root*, never the rest of the key: the root is all a
 * developer needs in order to act, and the remaining segments are request
 * parameters that have no business being printed. Without this the gate would
 * be silent, and a wine list quietly failing to survive a dead spot looks
 * exactly like a wine list that was never cached.
 */
function warnDenied(warned: Set<string>, root: string): void {
  if (!__DEV__ || warned.has(root)) return;
  warned.add(root);

  console.warn(
    `[query-persistence] Not persisting queries keyed on "${root}". The cache on ` +
      `disk is unencrypted AsyncStorage, so a key opts in explicitly or not at ` +
      `all. If these queries hold nothing personal and should survive a dead ` +
      `spot, add "${root}" to PERSISTED_QUERY_ROOTS in ` +
      `src/services/query-persistence.ts — and read the note above it first.`,
  );
}

export const shouldDehydrateQuery = createPersistenceGate(PERSISTED_QUERY_ROOTS);

/**
 * No mutation is ever persisted, and there is no allowlist for them.
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
