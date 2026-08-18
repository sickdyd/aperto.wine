/**
 * The one place that knows what a table URL looks like.
 *
 * Kept free of any React Native import so it can be tested — and reasoned
 * about — on its own: this regex is a security boundary as much as a parsing
 * convenience, since it is what stops an arbitrary scanned QR code from
 * pushing a route into the app.
 *
 * It must stay in step with the Rails route `get "t/:table_token"` under
 * `scope "(:locale)"`, and with the pathPrefix claimed in app.config.js.
 */
const TABLE_URL =
  /^https:\/\/(?:staging\.)?aperto\.wine\/(?:en\/|it\/)?t\/([A-Za-z0-9_-]+)$/;

export function extractTableToken(scanned: string): string | null {
  return TABLE_URL.exec(scanned)?.[1] ?? null;
}
