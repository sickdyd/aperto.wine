import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import { getLocales } from "expo-localization";

import en from "./locales/en.json";
import it from "./locales/it.json";

export const resources = { en: { translation: en }, it: { translation: it } };
export const SUPPORTED_LOCALES = ["it", "en"] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

/**
 * Italian is the default, not English — the Rails app runs `:it` in production
 * and the restaurants are Italian. A device in an unsupported language gets
 * Italian rather than English for the same reason.
 */
export const DEFAULT_LOCALE: SupportedLocale = "it";

export function resolveLocale(
  tags: readonly string[] = getLocales().map((l) => l.languageTag),
): SupportedLocale {
  for (const tag of tags) {
    // "en-GB" and "en" both mean English. Compare on the primary subtag only.
    const primary = tag.toLowerCase().split("-")[0];
    const match = SUPPORTED_LOCALES.find((l) => l === primary);
    if (match) return match;
  }
  return DEFAULT_LOCALE;
}

i18n.use(initReactI18next).init({
  resources,
  lng: resolveLocale(),
  fallbackLng: DEFAULT_LOCALE,
  interpolation: { escapeValue: false }, // React Native escapes on render
});

export default i18n;
