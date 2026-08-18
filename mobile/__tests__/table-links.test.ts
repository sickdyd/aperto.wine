import { extractTableToken } from "@/services/table-links";

describe("extractTableToken", () => {
  it("accepts a production table URL", () => {
    expect(extractTableToken("https://aperto.wine/t/abc123")).toBe("abc123");
  });

  it("accepts the locale-prefixed forms the Rails scope generates", () => {
    // routes.rb wraps everything in `scope "(:locale)"`, so /t/X and /en/t/X
    // are the same table.
    expect(extractTableToken("https://aperto.wine/en/t/abc123")).toBe("abc123");
    expect(extractTableToken("https://aperto.wine/it/t/abc123")).toBe("abc123");
  });

  it("accepts staging", () => {
    expect(extractTableToken("https://staging.aperto.wine/t/xyz")).toBe("xyz");
  });

  it("rejects another site's QR code", () => {
    expect(extractTableToken("https://evil.example/t/abc123")).toBeNull();
    expect(extractTableToken("https://aperto.wine.evil.example/t/abc")).toBeNull();
  });

  it("rejects plaintext http", () => {
    expect(extractTableToken("http://aperto.wine/t/abc123")).toBeNull();
  });

  it("rejects non-table paths on our own domain", () => {
    expect(extractTableToken("https://aperto.wine/owner/restaurants")).toBeNull();
    expect(extractTableToken("https://aperto.wine/some-restaurant")).toBeNull();
  });

  it("rejects arbitrary scanned text", () => {
    expect(extractTableToken("8001234567890")).toBeNull();
    expect(extractTableToken("")).toBeNull();
  });
});
