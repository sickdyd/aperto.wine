import AsyncStorage from "@react-native-async-storage/async-storage";
import { QueryClient, onlineManager } from "@tanstack/react-query";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import { persistQueryClientSave } from "@tanstack/react-query-persist-client";

import {
  PERSISTED_QUERY_ROOTS,
  createPersistenceGate,
  persistOptions,
  shouldDehydrateMutation,
} from "@/services/query-persistence";

/**
 * These tests run the real persistence path into an in-memory stand-in for
 * AsyncStorage and then read the bytes that landed there.
 *
 * Asserting on the bytes rather than on the option is the whole point. A test
 * that checked `dehydrateOptions.shouldDehydrateQuery` were defined would still
 * pass if the predicate returned `true` for everything.
 */
const mockStorage = new Map<string, string>();

jest.mock("@react-native-async-storage/async-storage", () => ({
  __esModule: true,
  default: {
    getItem: jest.fn(async (key: string) => mockStorage.get(key) ?? null),
    setItem: jest.fn(async (key: string, value: string) => {
      mockStorage.set(key, value);
    }),
    removeItem: jest.fn(async (key: string) => {
      mockStorage.delete(key);
    }),
  },
}));

/** Whatever the persister wrote, without coupling the test to its storage key. */
function persistedState(): { queries: { queryKey: unknown[] }[]; mutations: unknown[] } {
  const [raw] = [...mockStorage.values()];
  return raw ? JSON.parse(raw).clientState : { queries: [], mutations: [] };
}

const persistedKeys = () => persistedState().queries.map((query) => query.queryKey);
const persistedRaw = () => [...mockStorage.values()].join("");

let client: QueryClient;
let warn: jest.SpyInstance;

beforeEach(() => {
  mockStorage.clear();
  // `gcTime: Infinity` is the one non-default here, and it is not a shortcut:
  // every cached query and mutation otherwise schedules a five-minute garbage
  // collection timer on construction, and those timers hold jest's event loop
  // open long after the assertions have passed. Infinity skips scheduling
  // entirely (`isValidTimeout` rejects it), and nothing here wants collection.
  client = new QueryClient({
    defaultOptions: { queries: { gcTime: Infinity }, mutations: { gcTime: Infinity } },
  });
  // Every denial logs in development, and most of these tests deny by design.
  // Capturing the spy here keeps the suite output readable and gives the
  // discoverability test something to assert against.
  warn = jest.spyOn(console, "warn").mockImplementation(() => undefined);
});

afterEach(() => {
  warn.mockRestore();
  onlineManager.setOnline(true);
  client.clear();
});

/**
 * Same package, same (mocked) storage, and — the part that carries the whole
 * security policy — the very `dehydrateOptions` the app ships. The one
 * difference is the write throttle, which the shipped persister sets to a
 * second and holds in closure state that outlives an `it()` block, so a suite
 * built on it would spend almost all its time waiting out the previous test.
 * The first test below uses `persistOptions` verbatim so the shipped wiring is
 * still proved end to end.
 */
const unthrottled = {
  persister: createAsyncStoragePersister({ storage: AsyncStorage, throttleTime: 0 }),
  dehydrateOptions: persistOptions.dehydrateOptions,
};

const save = (options: typeof unthrottled | typeof persistOptions = unthrottled) =>
  persistQueryClientSave({ queryClient: client, ...options });

describe("the shipped persistence config", () => {
  it("keeps a personal query out of storage entirely", async () => {
    // The query this whole gate exists for: diner accounts are on the roadmap,
    // and nothing about them is allowlisted, so nothing about them is written.
    // Driven through `persistOptions` exactly as shipped — the object the root
    // layout hands to `PersistQueryClientProvider` — so this one covers the
    // wiring as well as the policy.
    client.setQueryData(["account", "bonuses"], {
      diner_email: "diner@example.com",
      bonus_balance_cents: 4500,
      discount_code: "MAGNUM20",
    });

    await save(persistOptions);

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("diner@example.com");
    expect(persistedRaw()).not.toContain("MAGNUM20");
    expect(persistedRaw()).not.toContain("4500");
  });

  it("persists nothing at all while the allowlist is empty", async () => {
    // Not a restatement of the test above: this one says the default is deny
    // for *every* key, not only the ones that look sensitive. A gate that
    // caught only the keys somebody remembered to worry about would not be a
    // default at all.
    client.setQueryData(["menu", "table-token"], { wines: [{ name: "Barolo 2016" }] });
    client.setQueryData(["restaurant", 1], { name: "Osteria" });
    client.setQueryData(["orders", "history"], [{ id: 7, total_cents: 8200 }]);

    await save();

    expect(PERSISTED_QUERY_ROOTS).toEqual([]);
    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("Barolo 2016");
    expect(persistedRaw()).not.toContain("8200");
  });

  it("never persists a paused mutation, allowlist or not", async () => {
    // TanStack's default keeps paused mutations so they can replay on
    // reconnect. An order is not replayable hours later, and its payload would
    // sit in plaintext for the whole wait.
    onlineManager.setOnline(false);

    const mutation = client.getMutationCache().build(client, {
      mutationKey: ["orders", "create"],
      mutationFn: async () => ({ ok: true }),
    });
    mutation.execute({ table_token: "abc", diner_phone: "+393331234567" }).catch(() => undefined);
    await Promise.resolve();

    expect(mutation.state.isPaused).toBe(true);

    await save();

    expect(persistedRaw()).not.toContain("+393331234567");
    expect(persistedState().mutations).toEqual([]);
    expect(shouldDehydrateMutation()).toBe(false);
  });

  it("says out loud, in development, why a query was not persisted", async () => {
    // The gate is only as good as its discoverability: the next developer meets
    // it here, at the moment they hit it, rather than in a security review
    // months later. A comment left behind by a deleted persister could not.
    client.setQueryData(["bonuses", "current"], { balance_cents: 100 });

    await save();

    expect(warn).toHaveBeenCalledWith(expect.stringContaining("PERSISTED_QUERY_ROOTS"));
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("bonuses"));
    // The root is enough to act on; the rest of the key is request parameters
    // and has no business being printed.
    expect(warn).not.toHaveBeenCalledWith(expect.stringContaining("current"));
  });
});

describe("the gate itself, against a populated allowlist", () => {
  // The shipped list is empty, so these drive the same rule with the root a
  // wine-list query would plausibly claim. Without them the suite could not
  // tell a working default-deny gate from one that simply refuses everything.
  const allowlisted = {
    ...unthrottled,
    dehydrateOptions: {
      shouldDehydrateQuery: createPersistenceGate(["menu"]),
      shouldDehydrateMutation,
    },
  };

  it("lets an allowlisted query through, so a loaded list survives a dead spot", async () => {
    client.setQueryData(["menu", "table-token"], { wines: [{ name: "Barolo 2016" }] });
    client.setQueryData(["account", "profile"], { name: "Roberto" });

    await save(allowlisted);

    expect(persistedKeys()).toEqual([["menu", "table-token"]]);
    expect(persistedRaw()).toContain("Barolo 2016");
    // One cache, one dehydration: the menu's presence must not carry the
    // account along with it.
    expect(persistedRaw()).not.toContain("Roberto");
  });

  it("still refuses a failed query whose root is allowlisted", async () => {
    // Overriding `shouldDehydrateQuery` replaces TanStack's success-only rule.
    // Composing with it rather than replacing it is what keeps an errored query
    // — which carries the failure, not the data — off the disk.
    await client
      .fetchQuery({
        queryKey: ["menu", "unreachable"],
        queryFn: () => Promise.reject(new Error("wifi died mid-service")),
        retry: false,
      })
      .catch(() => undefined);

    await save(allowlisted);

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("wifi died mid-service");
  });

  it("matches the root exactly rather than by prefix", async () => {
    // `includes` on the array of roots, never on the string: "menus" and
    // "menu-admin" are different keys, and an allowlist that matched them by
    // prefix would be a hole opened by nothing more than a plural.
    client.setQueryData(["menus", "all"], { leaked: "by-prefix" });
    client.setQueryData(["menu-admin", "1"], { leaked: "by-suffix" });

    await save(allowlisted);

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("leaked");
  });

  it("refuses a key whose root is not a string", async () => {
    // A key root can be an object or a number, and neither can ever be
    // allowlisted. Coercing one to a string to compare it would be the obvious
    // way to reopen the hole.
    client.setQueryData([{ scope: "menu" }, "x"], { leaked: "by-object" });
    client.setQueryData([42], { leaked: "by-number" });

    await save(allowlisted);

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("leaked");
  });
});
