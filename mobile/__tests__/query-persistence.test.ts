import AsyncStorage from "@react-native-async-storage/async-storage";
import { QueryClient, onlineManager } from "@tanstack/react-query";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import { persistQueryClientSave } from "@tanstack/react-query-persist-client";

import { persistOptions, shouldDehydrateMutation } from "@/services/query-persistence";

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

/** Seeds a successful query carrying `meta`, which `setQueryData` cannot set. */
function seed(queryKey: unknown[], data: unknown, meta?: { persist?: true }) {
  return client.fetchQuery({ queryKey, queryFn: async () => data, meta });
}

describe("the shipped persistence config", () => {
  it("keeps a query that never opted in out of storage entirely", async () => {
    // The query this whole gate exists for: diner accounts are on the roadmap,
    // and this one never asked to be persisted, so nothing about it is written.
    // Driven through `persistOptions` exactly as shipped — the object the root
    // layout hands to `PersistQueryClientProvider` — so this covers the wiring
    // as well as the policy.
    await seed(["account", "bonuses"], {
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

  it("persists nothing at all when no query has opted in", async () => {
    // Not a restatement of the test above: this one says the default is deny
    // for *every* query, not only the ones that look sensitive. A gate that
    // caught only what somebody remembered to worry about would not be a
    // default at all.
    await seed(["menu", "table-token"], { wines: [{ name: "Barolo 2016" }] });
    await seed(["restaurant", 1], { name: "Osteria" });
    await seed(["orders", "history"], [{ id: 7, total_cents: 8200 }]);

    await save();

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("Barolo 2016");
    expect(persistedRaw()).not.toContain("8200");
  });

  it("persists a query that opted in, so a loaded list survives a dead spot", async () => {
    await seed(["menu", "table-token"], { wines: [{ name: "Barolo 2016" }] }, { persist: true });
    await seed(["account", "profile"], { name: "Roberto" });

    await save();

    expect(persistedKeys()).toEqual([["menu", "table-token"]]);
    expect(persistedRaw()).toContain("Barolo 2016");
    // One cache, one dehydration: the opted-in query must not carry the
    // account along with it.
    expect(persistedRaw()).not.toContain("Roberto");
  });

  it("persists per query, not per key namespace", async () => {
    // The reason the flag lives on the query rather than in a list of key
    // roots. These two share a root; only the one that asked is written. A
    // list keyed on "menu" would have granted the namespace to both, which is
    // exactly how a personalised variant would slip onto disk later without
    // anyone re-deciding.
    await seed(["menu", "table-token"], { wines: [{ name: "Barolo 2016" }] }, { persist: true });
    await seed(["menu", "table-token", "diner-7"], { your_discount: "10% off, Roberto" });

    await save();

    expect(persistedKeys()).toEqual([["menu", "table-token"]]);
    expect(persistedRaw()).not.toContain("10% off");
  });

  it("treats anything other than an explicit true as no", async () => {
    // Fails closed on a typo or a truthy stand-in rather than guessing.
    await seed(["menu", "truthy"], { leaked: "by-truthy" }, { persist: 1 as unknown as true });
    await seed(["menu", "typo"], { leaked: "by-typo" }, { persits: true } as { persist?: true });

    await save();

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("leaked");
  });

  it("decides on the flag, not on the shape of the key", async () => {
    // Key roots can be objects or numbers. The old design refused those
    // outright, because it matched roots against a list and could not match
    // what it could not name. This one does not look at the key to decide at
    // all: an opted-in query is persisted whatever its key looks like, and one
    // that never opted in is refused whatever its key looks like.
    //
    // Worth pinning down because the persisted payload includes the key, so a
    // key carrying request parameters carries them to disk — which is a reason
    // to think before opting in, not a reason for the gate to second-guess a
    // decision the developer made explicitly.
    await seed([{ scope: "menu" }, "x"], { public_wine: "Barolo" }, { persist: true });
    await seed([42], { leaked: "by-number" });

    await save();

    expect(persistedKeys()).toEqual([[{ scope: "menu" }, "x"]]);
    expect(persistedRaw()).toContain("Barolo");
    expect(persistedRaw()).not.toContain("leaked");
  });

  it("still refuses a failed query that opted in", async () => {
    // Overriding `shouldDehydrateQuery` replaces TanStack's success-only rule.
    // Composing with it rather than replacing it is what keeps an errored query
    // — which carries the failure, not the data — off the disk.
    await client
      .fetchQuery({
        queryKey: ["menu", "unreachable"],
        queryFn: () => Promise.reject(new Error("wifi died mid-service")),
        meta: { persist: true },
        retry: false,
      })
      .catch(() => undefined);

    await save();

    expect(persistedKeys()).toEqual([]);
    expect(persistedRaw()).not.toContain("wifi died mid-service");
  });

  it("never persists a paused mutation, opted in or not", async () => {
    // TanStack's default keeps paused mutations so they can replay on
    // reconnect. An order is not replayable hours later, and its payload would
    // sit in plaintext for the whole wait.
    onlineManager.setOnline(false);

    const mutation = client.getMutationCache().build(client, {
      mutationKey: ["orders", "create"],
      mutationFn: async () => ({ ok: true }),
      meta: { persist: true },
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
    // months later. The root is unique to this test because the warning fires
    // once per key root.
    await seed(["bonuses", "current"], { balance_cents: 100 });

    await save();

    expect(warn).toHaveBeenCalledWith(expect.stringContaining("meta: { persist: true }"));
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("bonuses"));
    // It also has to say the part that matters most, and say it here rather
    // than only in a file the developer has no reason to open.
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("varies by which diner is asking"));
    // The root is enough to act on; the rest of the key is request parameters
    // and has no business being printed.
    expect(warn).not.toHaveBeenCalledWith(expect.stringContaining("current"));
  });
});
