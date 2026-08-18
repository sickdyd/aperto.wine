process.env.APP_VARIANT = "production";
const appConfig = require("../app.config.js").expo;

/**
 * The QR handoff only works while three things agree: the path the Rails app
 * routes, the path the app claims in associatedDomains / intentFilters, and the
 * expo-router file that renders it. Nothing fails loudly when they drift — the
 * link just quietly opens Safari instead of the app, on QR codes already
 * printed and glued to tables. So they are asserted against each other here.
 */
describe("universal link claims", () => {
  it("claims the production domain without a scheme prefix", () => {
    // "applinks:https://aperto.wine" is the classic mistake and silently
    // disables the association.
    expect(appConfig.ios.associatedDomains).toEqual(["applinks:aperto.wine"]);
  });

  it("claims the /t/ path prefix on Android with autoVerify", () => {
    const [filter] = appConfig.android.intentFilters;
    expect(filter.autoVerify).toBe(true);
    expect(filter.data).toEqual([
      { scheme: "https", host: "aperto.wine", pathPrefix: "/t/" },
    ]);
  });

  it("uses distinct bundle identifiers per variant", () => {
    const load = (variant: string) => {
      process.env.APP_VARIANT = variant;
      jest.resetModules();
      return require("../app.config.js").expo;
    };

    expect(load("production").ios.bundleIdentifier).toBe("wine.aperto.app");
    expect(load("staging").ios.bundleIdentifier).toBe("wine.aperto.app.staging");
    expect(load("development").ios.bundleIdentifier).toBe("wine.aperto.app.dev");
  });

  it("points non-production builds at the staging host", () => {
    process.env.APP_VARIANT = "staging";
    jest.resetModules();
    const staging = require("../app.config.js").expo;
    expect(staging.ios.associatedDomains).toEqual(["applinks:staging.aperto.wine"]);
  });

  it("keeps the splash on paper rather than white", () => {
    process.env.APP_VARIANT = "production";
    jest.resetModules();
    expect(require("../app.config.js").expo.splash.backgroundColor).toBe("#F6F2E9");
  });
});
