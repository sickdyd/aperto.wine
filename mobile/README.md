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
  services/     api client, table-link parsing
  stores/       zustand; tokens live in SecureStore, never AsyncStorage
  types/        zod schemas for API payloads
```
