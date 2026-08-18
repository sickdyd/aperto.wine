import { readFileSync } from "fs";
import { join } from "path";

// Metro does not tree shake. `@expo-google-fonts/<family>` re-exports every
// weight and italic of that family, so importing the package root ships the
// lot — 28 typefaces, 6.7MB, where the app renders four faces. Importing the
// per-weight subpath is the whole of what keeps the bundle to those four.
//
// Both import forms hand `useFonts` the identical asset id at runtime, so no
// runtime assertion can tell them apart — the difference exists only in the
// module graph Metro walks. Hence the checks on the import statement itself.
//
// What this file CANNOT catch, because it only reads this one source file:
// a font imported from any other module, a font a dependency carries in on its
// own, or non-font assets bloating the bundle. All of those leave these tests
// green. `npm run check:bundle` exports a real iOS bundle and asserts on what
// actually shipped, which is the check that covers those; this file is the
// fast, precise diagnostic for the common case, not the safety net.
const FACES = [
  ["@expo-google-fonts/instrument-serif/400Regular", "InstrumentSerif_400Regular"],
  ["@expo-google-fonts/eb-garamond/400Regular", "EBGaramond_400Regular"],
  ["@expo-google-fonts/eb-garamond/500Medium", "EBGaramond_500Medium"],
  ["@expo-google-fonts/jetbrains-mono/400Regular", "JetBrainsMono_400Regular"],
] as const;

const layout = readFileSync(join(__dirname, "../src/app/_layout.tsx"), "utf8");
const fontImports = layout.match(/from ["']@expo-google-fonts\/[^"']+["']/g) ?? [];
const loadedFaces = layout.match(/useFonts\(\{([^}]*)\}\)/)?.[1] ?? "";

describe("bundled typefaces", () => {
  it.each(FACES)("%s resolves and exports %s", (subpath, face) => {
    expect(require(subpath)[face]).toBeDefined();
  });

  it.each(FACES)("the root layout loads %s", (subpath, face) => {
    expect(layout).toMatch(
      new RegExp(`import \\{\\s*${face}\\s*\\} from ["']${subpath}["']`)
    );
    expect(loadedFaces.split(",").map((s) => s.trim())).toContain(face);
  });

  it("imports no font beyond those four", () => {
    expect(fontImports).toHaveLength(FACES.length);
  });

  it("never imports a font package root", () => {
    // A root path has no second segment: "@expo-google-fonts/eb-garamond".
    expect(fontImports.filter((i) => !/@expo-google-fonts\/[^/"']+\//.test(i))).toEqual([]);
  });
});
