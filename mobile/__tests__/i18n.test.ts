import * as fs from "fs";
import * as path from "path";

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

describe("unused keys", () => {
  // The Rails suite fails on keys defined but never referenced (i18n-tasks, see
  // config/i18n-tasks.yml). Dead copy is worse here than there: a translator is
  // paid to render strings that ship to nobody, and a key that looks live is a
  // key nobody deletes.
  function sourceFiles(dir: string): string[] {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) return sourceFiles(full);
      return /\.tsx?$/.test(entry.name) ? [full] : [];
    });
  }

  it("references every key it defines", () => {
    const src = path.join(__dirname, "..", "src");
    const corpus = sourceFiles(src)
      .map((file) => fs.readFileSync(file, "utf8"))
      .join("\n");

    const defined = keyPaths(resources[DEFAULT_LOCALE].translation);
    const unused = defined.filter((key) => !corpus.includes(`"${key}"`));

    expect(unused).toEqual([]);
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
