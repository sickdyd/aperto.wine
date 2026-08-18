#!/usr/bin/env node
// Asserts what an iOS export actually ships, by exporting one and reading its
// asset map.
//
// This exists because `__tests__/fonts.test.ts` can only see import statements.
// That catches the regression we know about — someone importing a font package
// root, which drags in every weight and italic of the family — but it is a
// proxy, and a proxy stays green while the bundle grows for any reason it does
// not scan: a dependency that carries its own fonts, an import from a file
// other than the root layout, a 4MB PNG. Those only show up in a release
// export, which nothing else here runs.
//
// The font check is exact rather than a budget: the set of typefaces in the
// bundle must equal the set the root layout imports. Anything the layout did
// not ask for is a regression whatever it weighs, and a face the layout asks
// for but the bundle lacks means the app renders a fallback. Deriving the
// expectation from the layout rather than a hardcoded list keeps this honest
// when a face is legitimately added or dropped — nothing to update here.
//
// The byte budget is the loose backstop for everything else. It is deliberately
// slack: fonts are already pinned exactly, so this only needs to catch
// something unexpectedly enormous.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const MOBILE = join(dirname(fileURLToPath(import.meta.url)), "..");
const LAYOUT = join(MOBILE, "src/app/_layout.tsx");

// Raise this only alongside a deliberate decision that the app should ship more
// than it does today, and say so in the commit. It is not a number to nudge
// upward until CI goes quiet.
const TOTAL_ASSET_BUDGET = 2_000_000;

const bytes = (n) => `${n.toLocaleString("en-US")} B`;

// Every face the root layout imports, e.g. `EBGaramond_400Regular`. The binding
// name and the .ttf asset name are the same string, which is what lets the two
// sides be compared directly.
function facesImportedByLayout() {
  const src = readFileSync(LAYOUT, "utf8");
  const faces = new Set();
  for (const m of src.matchAll(
    /import\s*\{([^}]+)\}\s*from\s*["']@expo-google-fonts\/[^"']+["']/g
  )) {
    for (const name of m[1].split(",")) {
      const face = name.trim();
      if (face) faces.add(face);
    }
  }
  return faces;
}

function exportBundle(outDir) {
  execFileSync(
    "npx",
    ["expo", "export", "--platform", "ios", "--dump-assetmap", "--output-dir", outDir],
    { cwd: MOBILE, stdio: "inherit" }
  );
  const assetmap = JSON.parse(readFileSync(join(outDir, "assetmap.json"), "utf8"));
  return Object.values(assetmap).map((a) => ({
    name: a.name,
    type: a.type,
    // A single asset can be several files (@2x/@3x variants); all of them ship.
    size: a.files.reduce((sum, f) => sum + statSync(f).size, 0),
  }));
}

const outDir = mkdtempSync(join(tmpdir(), "aperto-bundle-"));
let assets;
try {
  assets = exportBundle(outDir);
} finally {
  rmSync(outDir, { recursive: true, force: true });
}

const fonts = assets.filter((a) => a.type === "ttf" || a.type === "otf");
const total = assets.reduce((sum, a) => sum + a.size, 0);
const fontBytes = fonts.reduce((sum, a) => sum + a.size, 0);

const expected = facesImportedByLayout();
const bundled = new Set(fonts.map((a) => a.name));
const unexpected = [...bundled].filter((n) => !expected.has(n)).sort();
const missing = [...expected].filter((n) => !bundled.has(n)).sort();

console.log(`\nTypefaces bundled (${fonts.length}), ${bytes(fontBytes)}:`);
for (const f of [...fonts].sort((a, b) => a.name.localeCompare(b.name))) {
  console.log(`  ${String(f.size).padStart(9)}  ${f.name}`);
}
console.log(
  `\nAssets: ${assets.length}, ${bytes(total)} of ${bytes(TOTAL_ASSET_BUDGET)} budget ` +
    `(${bytes(TOTAL_ASSET_BUDGET - total)} spare)\n`
);

const failures = [];
if (unexpected.length) {
  failures.push(
    `Bundle carries ${unexpected.length} typeface(s) the root layout never imports:\n` +
      unexpected.map((n) => `    ${n}`).join("\n") +
      `\n  Importing a font package root pulls in the whole family — use the\n` +
      `  per-weight subpath, e.g. "@expo-google-fonts/eb-garamond/400Regular".\n` +
      `  If the font comes from a dependency instead, exclude it in metro.config.js.`
  );
}
if (missing.length) {
  failures.push(
    `Root layout imports ${missing.length} typeface(s) that never reached the bundle:\n` +
      missing.map((n) => `    ${n}`).join("\n") +
      `\n  The app will silently render a system fallback for these.`
  );
}
if (total > TOTAL_ASSET_BUDGET) {
  failures.push(
    `Assets total ${bytes(total)}, over the ${bytes(TOTAL_ASSET_BUDGET)} budget by ` +
      `${bytes(total - TOTAL_ASSET_BUDGET)}.`
  );
}

if (failures.length) {
  console.error("Bundle check failed.\n");
  for (const f of failures) console.error(`  ${f}\n`);
  process.exit(1);
}
console.log("Bundle check passed.");
