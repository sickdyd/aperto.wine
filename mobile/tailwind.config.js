// The Sommelier's Ledger, ported from the web theme.
//
// This is a deliberate hand-copy of the tokens in the Rails app's
// app/assets/tailwind/application.css @theme block, not an import: the web is on
// Tailwind 4 and NativeWind 4 pins Tailwind 3.4, so the two cannot share a
// config file. When a token changes on the web it has to change here too —
// __tests__/design-tokens.test.ts fails if the two ever disagree on the ramp.
/** @type {import('tailwindcss').Config} */
module.exports = {
  presets: [require("nativewind/preset")],
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // the oxblood ramp — five steps, each with a job
        ox: {
          1: "#4A1219", // deepest — masthead band, heavy section rules
          2: "#6E1F2A", // core    — headings, wordmark, prices, actions
          3: "#8E2A36", // mid     — medium rules, numerals, active state
          4: "#B25563", // light   — hairlines, inactive chips, never text
          5: "#E8D5D6", // tint    — banded ground, type on deep ground
        },
        // warm paper stocks
        paper: "#F6F2E9",
        stock: "#E8DCC6",
        "stock-pale": "#EFE8DA",
        sheet: "#FCFAF4",
        // ink — body copy only, never structure
        ink: "#221A15",
        "ink-soft": "#514A44",
        quiet: "#5F5436",
        "on-deep": "#F3E7E4",
        "on-deep-soft": "#D9BDBD",
        // wine varietal marks
        wine: {
          red: "#722F37",
          white: "#EFDCA0",
          rose: "#E8A0A0",
          sparkling: "#E6C548",
          dessert: "#C79426",
        },
      },
      fontFamily: {
        display: ["InstrumentSerif_400Regular", "serif"],
        body: ["EBGaramond_400Regular", "serif"],
        "body-medium": ["EBGaramond_500Medium", "serif"],
        mono: ["JetBrainsMono_400Regular", "monospace"],
      },
      // Zero radius everywhere. The ledger has rules, not boxes.
      borderRadius: { none: "0", DEFAULT: "0", sm: "0", md: "0", lg: "0", xl: "0", full: "0" },
    },
  },
  plugins: [],
};
