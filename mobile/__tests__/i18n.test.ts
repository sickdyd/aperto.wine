import { resources, resolveLocale, DEFAULT_LOCALE, SUPPORTED_LOCALES } from "@/i18n";

/** Every leaf key path in an object, as dot-joined strings. */
function keyPaths(value: unknown, prefix = ""): string[] {
  if (typeof value !== "object" || value === null) return [prefix];
  return Object.entries(value).flatMap(([k, v]) =>
    keyPaths(v, prefix ? `${prefix}.${k}` : k),
  );
}

describe("locale parity", () => {
  // The Rails suite fails on any key present in one locale file and missing
  // from the other (test/i18n_test.rb). The same drift is just as easy to
  // introduce here and just as invisible, so it is caught the same way.
  it("defines exactly the same keys in every locale", () => {
    const [reference, ...others] = SUPPORTED_LOCALES;
    const expected = keyPaths(resources[reference].translation).sort();

    for (const locale of others) {
      expect(keyPaths(resources[locale].translation).sort()).toEqual(expected);
    }
  });

  it("has no empty strings", () => {
    for (const locale of SUPPORTED_LOCALES) {
      const flat = JSON.stringify(resources[locale].translation);
      expect(flat).not.toContain('""');
    }
  });
});

describe("resolveLocale", () => {
  it("matches on the primary subtag, so en-GB is English", () => {
    expect(resolveLocale(["en-GB"])).toBe("en");
    expect(resolveLocale(["it-IT"])).toBe("it");
  });

  it("takes the first supported tag in the device's order of preference", () => {
    expect(resolveLocale(["fr-FR", "en-US", "it-IT"])).toBe("en");
  });

  it("falls back to Italian, not English, for unsupported languages", () => {
    // Production Rails runs :it and the restaurants are Italian — a German
    // phone should get the language the room is in, not the lingua franca.
    expect(resolveLocale(["de-DE"])).toBe(DEFAULT_LOCALE);
    expect(resolveLocale([])).toBe("it");
  });
});
