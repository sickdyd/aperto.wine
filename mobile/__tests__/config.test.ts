describe("config.apiUrl", () => {
  const ORIGINAL = process.env.EXPO_PUBLIC_API_URL;

  afterEach(() => {
    process.env.EXPO_PUBLIC_API_URL = ORIGINAL;
    jest.resetModules();
  });

  function loadConfig() {
    let loaded: typeof import("@/constants/config").config;
    jest.isolateModules(() => {
      loaded = require("@/constants/config").config;
    });
    return loaded!;
  }

  it("strips trailing slashes so paths do not double up", () => {
    process.env.EXPO_PUBLIC_API_URL = "https://aperto.wine/api/v1/";
    expect(loadConfig().apiUrl).toBe("https://aperto.wine/api/v1");
  });

  it("strips several trailing slashes", () => {
    process.env.EXPO_PUBLIC_API_URL = "https://aperto.wine/api/v1///";
    expect(loadConfig().apiUrl).toBe("https://aperto.wine/api/v1");
  });

  it("falls back to the local Rails port when unset", () => {
    delete process.env.EXPO_PUBLIC_API_URL;
    // bin/dev serves on 4010 (Procfile.dev), not Rails' default 3000.
    expect(loadConfig().apiUrl).toBe("http://localhost:4010/api/v1");
  });
});
