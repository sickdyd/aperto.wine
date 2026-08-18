# aperto.wine — mobile

Expo / React Native client for aperto.wine, scaffolded against the stack used in
`../jeero` (expo-router, NativeWind, TanStack Query, zustand, i18next, Sentry,
EAS, jest-expo, Maestro) on current SDK versions rather than jeero's pinned ones.

## Status: scaffold

The app builds, bundles, typechecks and tests green. It does **not** yet talk to
a server, because there is nothing to talk to: the Rails app is entirely HTML
controllers with session-cookie auth and has no `api/v1` namespace. The client in
`src/services/api.ts` is written against the contract jeero's `Api::V1`
established — Bearer access token, `X-Locale`, a `{ error: { code, message } }`
envelope — so the server can be built to meet it.

## Commands

```sh
npm start          # dev server, API pointed at this machine's LAN IP on :4010
npm run ios        # native run (requires a development build)
npm test           # jest
npm run typecheck  # tsc --noEmit
npm run lint       # expo lint
```

`npm start` derives the API URL from `ipconfig getifaddr en0` because a phone on
wifi cannot reach the host's `localhost`. Rails must be running via `bin/dev`
(port 4010, per `Procfile.dev`).

## The QR handoff

A table QR encodes a plain `https://aperto.wine/t/TOKEN` URL — the same URL it
has always encoded. With the app installed, iOS/Android open it in the app; with
the app absent, the browser opens the web menu exactly as before. No branching
logic, and every table tent already printed keeps working.

Three things have to stay in agreement for that to hold, and none of them fails
loudly when they drift:

| Where | What |
|---|---|
| `config/routes.rb` (Rails) | `get "t/:table_token"` under `scope "(:locale)"` |
| `app.config.js` | `ios.associatedDomains` + `android.intentFilters` claiming `/t/` |
| `src/app/t/[token].tsx` | the expo-router file that renders it |

`__tests__/universal-links.test.ts` asserts the second against the first.

**Still outstanding on the server side:** the Rails app must serve
`/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json`.
Neither can be written until there is an Apple Developer Team ID and an Android
signing certificate, so they are deliberately not in this branch — an AASA with a
placeholder Team ID is worse than none, since iOS caches the file at install time
and a wrong one needs an App Store update to correct.

## What is allowed offline

Restaurant wifi is unreliable, so the query cache is persisted to disk — a diner
who has already loaded a wine list keeps seeing it through a dead spot. The store
behind that is AsyncStorage: plain unencrypted files, readable on a rooted or
jailbroken device and swept into iCloud/Google device backups. Tokens already
avoid it for exactly that reason (`src/stores/auth-store.ts` uses SecureStore).

TanStack Query persists **every** successful query by default. That default is
opt-out, and opt-out is the wrong shape here: diner accounts, bonuses, discounts
and order history are on the roadmap, and the day those queries exist they would
land in plaintext silently, with nobody having decided they should.

So `src/services/query-persistence.ts` inverts it. A query reaches the disk only
by saying so itself, and no mutation is ever persisted — an order replayed off
disk hours later would be a different order than the diner built, against a
cellar that has moved.

```ts
useQuery({
  queryKey: ["menu", tableToken],
  queryFn: fetchMenu,
  meta: { persist: true }, // public wine list; safe in a plaintext backup
})
```

### Before you write that flag

**Would we be relaxed about this sitting in an unencrypted backup of a phone we
do not control?**

A restaurant's published wine list is already public — it is what the QR code
hands to anyone who scans it. The answer is yes, and that is roughly the only
thing it is yes for.

The trap is not the obviously-sensitive query; nobody persists an order history
by accident. It is **personalisation**, because a personalised screen looks like
the same screen. A menu showing "your 10% off", a price adjusted for a returning
regular, a list reordered by what this diner drank last time — same route, same
component, often the same query key, and now the response varies by *who is
asking*. That is not public, and it must not be persisted.

So the real test is narrower than "does this contain PII": **does the response
vary by which diner is asking?** If yes, it does not get the flag. It belongs in
memory for the session, or in SecureStore if it genuinely has to outlive the
process.

**If a persisted query later becomes diner-specific, remove the flag.** That is
the change, and it is one line.

### Why the flag lives on the query

An allowlist of query key roots kept in `query-persistence.ts` would be easier
to audit, and was the first design. It was replaced because it grants a
*namespace* once and forever: allowlist `menu`, and the day a menu becomes
diner-specific the payload changes, the key does not, and the list cannot see it
happen. Nobody edits that file, so nobody re-decides.

Written on the query, `persist: true` sits three lines from the `queryFn` whose
response just gained a discount — same object, same diff, same reviewer. The
flag is typed through TanStack's `Register` augmentation, so `meta: { persist:
true }` is checked rather than a loose string bag, and anything that is not
literally `true` fails closed.

The trade is auditability. The array answered "what leaves this device?" in one
file; the answer is now `grep -rn "persist: true" src/`, which is a convention
rather than a mechanism — a shared constant or a spread would satisfy the type
and defeat a literal grep. That is worth a lint rule or an inventory test once
there is an inventory; with zero opted-in queries today there is nothing for
one to check, and a tripwire guarding an empty set is how the previous design
got into trouble. Add it alongside the first `persist: true`.

A query that has not opted in is dropped, and says so in the console in
development, naming the key root and the personalisation question. That failure
is safe in the direction that matters: less on disk, never more.
`__tests__/query-persistence.test.ts` drives the real persister into an
in-memory AsyncStorage and asserts on the bytes that land there rather than on
the option being set — including that two queries sharing a key root do not
share a decision.

## Design

`tailwind.config.js` is a hand-port of the Sommelier's Ledger tokens from the web
app's `app/assets/tailwind/application.css`. It is a copy, not an import: the web
runs Tailwind 4 and NativeWind 4 pins Tailwind 3.4, so one config cannot serve
both. When a token changes on the web, change it here too.

Zero border radius, no shadows, warm paper grounds, oxblood as structure — see
`PRODUCT.md` in the repo root before touching UI.

## Layout

```
src/
  app/          expo-router routes (t/[token].tsx is the universal-link target)
  components/   ledger primitives (Rule, …)
  constants/    build-time configuration
  i18n/         it (default) + en, kept at parity by a test
  services/     api client, table-link parsing, the offline-cache gate
  stores/       zustand; tokens live in SecureStore, never AsyncStorage
  types/        zod schemas for API payloads
```
