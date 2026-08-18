import { readFileSync } from "fs";
import { join } from "path";
import { inflateSync } from "zlib";

process.env.APP_VARIANT = "production";
const appConfig = require("../app.config.js").expo;

/**
 * Icon mistakes are all silent. An app icon carrying an alpha channel is not
 * rejected until the App Store upload, at the end of a build; a notification
 * icon that is not a white-on-transparent silhouette renders a solid white
 * square on the status bar rather than erroring; a splash image that is opaque
 * bands its own rectangle across the paper ground. None of it shows up in a
 * simulator run of the happy path, so the headers and the pixels are asserted
 * here instead.
 *
 * What is NOT asserted here is geometry — whether the art clears the launcher
 * mask circles. `script/build_brand_icons.py` checks that as it writes, since
 * it is the only thing that knows the intended proportions.
 *
 * Regenerate the whole set with that script rather than hand-editing a file to
 * satisfy one of these.
 */

const IMAGES = join(__dirname, "..", "assets", "images");

// PNG colour types. 2 and 0 carry no alpha channel at all; 6 and 4 do.
const RGB = 2;
const RGBA = 6;
const CHANNELS: Record<number, number> = { 0: 1, 2: 3, 4: 2, 6: 4 };

type Png = { width: number; height: number; colorType: number };
type Pixel = { r: number; g: number; b: number; a: number };

function chunks(buf: Buffer) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (!buf.subarray(0, 8).equals(signature)) throw new Error("not a PNG");
  const found: { type: string; data: Buffer }[] = [];
  for (let at = 8; at < buf.length; ) {
    const length = buf.readUInt32BE(at);
    found.push({
      type: buf.toString("ascii", at + 4, at + 8),
      data: buf.subarray(at + 8, at + 8 + length),
    });
    at += length + 12; // length + type + data + crc
  }
  return found;
}

function readPng(name: string): Png {
  const ihdr = chunks(readFileSync(join(IMAGES, name))).find((c) => c.type === "IHDR")!;
  return {
    width: ihdr.data.readUInt32BE(0),
    height: ihdr.data.readUInt32BE(4),
    colorType: ihdr.data.readUInt8(9),
  };
}

/**
 * Decode to pixels. Only the shapes this project emits are handled — 8-bit,
 * non-interlaced — and anything else throws rather than being quietly wrong.
 */
function decode(name: string): { width: number; height: number; at: (x: number, y: number) => Pixel } {
  const parsed = chunks(readFileSync(join(IMAGES, name)));
  const ihdr = parsed.find((c) => c.type === "IHDR")!;
  const width = ihdr.data.readUInt32BE(0);
  const height = ihdr.data.readUInt32BE(4);
  const [depth, colorType, , , interlace] = [8, 9, 10, 11, 12].map((i) => ihdr.data.readUInt8(i));
  if (depth !== 8 || interlace !== 0) throw new Error(`${name}: unsupported PNG encoding`);

  const bpp = CHANNELS[colorType];
  const stride = width * bpp;
  const raw = inflateSync(
    Buffer.concat(parsed.filter((c) => c.type === "IDAT").map((c) => c.data)),
  );
  const out = Buffer.alloc(height * stride);

  // Undo the per-scanline filters (PNG spec §9.2). Each row is preceded by one
  // filter-type byte and is reconstructed against the row above it.
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? out[y * stride + i - bpp] : 0;
      const b = y > 0 ? out[(y - 1) * stride + i] : 0;
      const c = i >= bpp && y > 0 ? out[(y - 1) * stride + i - bpp] : 0;
      let add = 0;
      if (filter === 1) add = a;
      else if (filter === 2) add = b;
      else if (filter === 3) add = (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const [pa, pb, pc] = [Math.abs(p - a), Math.abs(p - b), Math.abs(p - c)];
        add = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else if (filter !== 0) throw new Error(`${name}: bad filter ${filter}`);
      out[y * stride + i] = (src[i] + add) & 0xff;
    }
  }

  const at = (x: number, y: number): Pixel => {
    const i = y * stride + x * bpp;
    return { r: out[i], g: out[i + 1], b: out[i + 2], a: bpp === 4 ? out[i + 3] : 255 };
  };
  return { width, height, at };
}

function corners(name: string): Pixel[] {
  const img = decode(name);
  return [
    img.at(0, 0),
    img.at(img.width - 1, 0),
    img.at(0, img.height - 1),
    img.at(img.width - 1, img.height - 1),
  ];
}

describe("app icons", () => {
  it("ships an iOS app icon at 1024x1024 with no alpha channel", () => {
    // Not "alpha that happens to be opaque" — App Store Connect rejects the
    // channel's presence, so the file must be colour type 2.
    expect(readPng("icon.png")).toEqual({ width: 1024, height: 1024, colorType: RGB });
  });

  it("ships adaptive icon layers at 1024x1024 with transparency", () => {
    for (const layer of ["android-icon-foreground.png", "android-icon-monochrome.png"]) {
      expect(readPng(layer)).toEqual({ width: 1024, height: 1024, colorType: RGBA });
      // The launcher composites these over the background layer; an opaque
      // corner would paint a square out to the mask edge.
      expect(corners(layer).map((p) => p.a)).toEqual([0, 0, 0, 0]);
    }
  });

  it("ships a 96x96 notification icon that is white wherever it is not transparent", () => {
    // Android reads this file's alpha channel and nothing else, but the colour
    // has to be white so the silhouette survives being drawn untinted.
    expect(readPng("notification-icon.png")).toEqual({ width: 96, height: 96, colorType: RGBA });
    const img = decode("notification-icon.png");
    let opaque = 0;
    for (let y = 0; y < img.height; y++) {
      for (let x = 0; x < img.width; x++) {
        const p = img.at(x, y);
        if (p.a === 0) continue;
        opaque++;
        expect([p.r, p.g, p.b]).toEqual([255, 255, 255]);
      }
    }
    // A fully transparent file would satisfy the loop above without drawing
    // anything at all.
    expect(opaque).toBeGreaterThan(500);
  });

  it("ships a monochrome layer drawn in a single flat colour", () => {
    // Android 13+ discards the colour and re-tints; two tones in the source
    // would flatten unpredictably.
    const img = decode("android-icon-monochrome.png");
    const tones = new Set<string>();
    for (let y = 0; y < img.height; y++) {
      for (let x = 0; x < img.width; x++) {
        const p = img.at(x, y);
        if (p.a === 255) tones.add(`${p.r},${p.g},${p.b}`);
      }
    }
    expect(tones.size).toBe(1);
  });

  it("ships a transparent splash lockup, so it sits on the paper ground", () => {
    // An opaque splash image would band its own rectangle across
    // splash.backgroundColor.
    expect(readPng("splash-icon.png").colorType).toBe(RGBA);
    expect(corners("splash-icon.png").map((p) => p.a)).toEqual([0, 0, 0, 0]);
  });

  it("ships a 196x196 favicon", () => {
    expect(readPng("favicon.png")).toEqual({ width: 196, height: 196, colorType: RGB });
  });
});

describe("icon wiring", () => {
  it("points every icon key at a file that exists and decodes", () => {
    const referenced = [
      appConfig.icon,
      appConfig.splash.image,
      appConfig.web.favicon,
      appConfig.android.adaptiveIcon.foregroundImage,
      appConfig.android.adaptiveIcon.monochromeImage,
    ];
    for (const path of referenced) {
      expect(typeof path).toBe("string");
      expect(() => readPng(path.replace("./assets/images/", ""))).not.toThrow();
    }
  });

  it("gives Android 13+ a monochrome layer rather than a shrunken colour icon", () => {
    expect(appConfig.android.adaptiveIcon.monochromeImage).toBe(
      "./assets/images/android-icon-monochrome.png",
    );
  });

  it("keeps the adaptive background a flat paper token, not an image", () => {
    // backgroundImage would override backgroundColor, and the ground is one
    // colour — there is nothing for a PNG to carry.
    expect(appConfig.android.adaptiveIcon.backgroundColor).toBe("#F6F2E9");
    expect(appConfig.android.adaptiveIcon.backgroundImage).toBeUndefined();
  });

  it("gives expo-notifications its own silhouette, never the app icon", () => {
    const [, props] = appConfig.plugins.find(
      (p: unknown) => Array.isArray(p) && p[0] === "expo-notifications",
    );
    expect(props.icon).toBe("./assets/images/notification-icon.png");
    expect(props.icon).not.toBe(appConfig.icon);
    expect(props.color).toBe("#6E1F2A");
  });
});
