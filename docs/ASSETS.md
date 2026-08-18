# Asset Sourcing Reference

Where to look when a new icon, SVG, or illustration is needed. Check the sources
in order — most needs are covered by what is already installed locally.

## 1. Already installed (check first)

### Phosphor icons (full set, local install)

- **Location:** `app/assets/svg/icons/phosphor/{thin,light,regular,bold,fill,duotone}/`
- **Note:** `app/assets/svg/icons` is **gitignored** — the set is installed per
  checkout, not committed. In a fresh clone or worktree, restore it with
  `bin/rails generate rails_icons:install --libraries=phosphor` (or copy the
  directory from another checkout). Tests fail with "Icon not found" until it exists.
- **License:** MIT — no attribution required.
- **Rendered via** the `rails_icons` gem (configured in `config/initializers/rails_icons.rb`,
  default library `phosphor`, default variant `regular`, default css `size-5`):

  ```erb
  <%= icon "wine", variant: "regular", css: "size-4 opacity-70" %>
  ```

- Browse names at <https://phosphoricons.com> or `ls app/assets/svg/icons/phosphor/regular/`.
- Wine-relevant icons available: `wine`, `cheers`, `champagne`, `brandy`, `martini`,
  `beer-bottle`.

### Wine color dots

- **CSS:** `.wine-dot` base class plus `.wine-dot-<color>` modifiers (red, white, rose,
  sparkling, dessert) in `app/assets/tailwind/application.css`.
- **Rendered via** `wine_color_dot(color, label: true)` in `app/helpers/wines_helper.rb` —
  a small wine-type color marker used on the public menu rows, color section headers,
  and owner wine lists. Pass `label: false` when visible text next to the dot already
  names the color; otherwise it appends a screen-reader-only label.

## 2. Cherry-pick from other MIT/ISC icon libraries

For UI icons Phosphor lacks. Copy only the SVGs needed into
`app/assets/svg/icons/<library>/<variant>/` (so `rails_icons` can serve them). Do
**not** add npm/gem dependencies for a handful of icons.

Beware: `app/assets/svg/icons` is gitignored, so a cherry-picked SVG dropped there
will NOT be committed. Either carve out an exception in `.gitignore` for the specific
file(s), or list them in this doc so other checkouts know to fetch them.

| Library | License | URL | Notable wine-domain icons |
|---|---|---|---|
| Tabler Icons | MIT | <https://tabler.io/icons> · [repo](https://github.com/tabler/tabler-icons) | `grape`, `barrel`, `bottle`, `glass`, `glass-full`, `glass-champagne`, `glass-cocktail`, `glass-gin` |
| Lucide | ISC | <https://lucide.dev> · [repo](https://github.com/lucide-icons/lucide) | `bottle-wine`, `barrel`, `amphora` |
| Heroicons | MIT | <https://heroicons.com> | General UI only, matches Tailwind aesthetics |

Style note: Tabler/Lucide are 2px-stroke outline sets — they blend with Phosphor
`regular`/`light`, not with `fill`/`duotone`. Adjust `stroke-width` if needed for
visual consistency.

To search a repo for icon names without a browser (icon sites are JS-rendered):

```sh
gh api repos/lucide-icons/lucide/contents/icons --paginate --jq '.[].name' | grep -i wine
```

## 3. Decorative / illustrative SVGs

For landing pages, empty states, marketing sections — richer wine imagery
(grapes, vineyard, corkscrew, decanter, cork, cellar).

| Source | License | URL | Notes |
|---|---|---|---|
| SVG Repo | CC0 (per-collection, verify on the icon page) | <https://www.svgrepo.com> | "Winery" collections: grapes, corkscrew, cork, wine bottle. Safe to vendor, no attribution. |
| FreeSVG | CC0 | <https://freesvg.org> | Decanter, corkscrew, bottle-and-glass illustrations. |
| Reshot | Reshot license (free commercial, no attribution) | <https://www.reshot.com/free-svg-icons/wine/> | ~131 wine icons, more illustrative style. |
| unDraw | Open license (no attribution) | <https://undraw.co> | Flat illustrations, recolorable to brand palette. |

Reachability, checked 2026-08-05: Openclipart's JSON API returns empty bodies,
publicdomainvectors.net did not resolve, and SVG Repo answers scripted requests
with HTTP 429. FreeSVG works but its download endpoint needs a `Referer` header
pointing at the item page, or it serves 0 bytes.

### Museum open-access collections

Where to go when the need is a period engraving rather than an icon. All CC0 or
public domain, all direct-downloadable, no key.

| Source | URL | Notes |
|---|---|---|
| Wikimedia Commons | `https://commons.wikimedia.org/w/api.php` | Best yield. Mirrors Rijksmuseum, British Museum and Cooper Hewitt objects. Check `extmetadata.LicenseShortName` per file — the mix of PD and CC BY-SA is not obvious from the image. Send a descriptive User-Agent. |
| Met Open Access | `https://collectionapi.metmuseum.org/public/collection/v1/` | No key, but bot-blocks on repeated queries. Filter on `isPublicDomain`. |
| Rijksmuseum / British Museum | via Commons | Trade cards, shop signs and catalogue plates are the richest source of isolated, hard-line drawings of objects. |

Caveat learnt the hard way: isolated black-line engravings of a *bottle and
glass together* barely exist in the public domain. Most PD wine imagery is oil
painting, tavern scenes with figures, or photographs of artifacts. Expect to
crop a usable object out of a larger plate.

### The hero engraving

`app/views/shared/_engraving.html.erb` — the bottle and glass on the landing
page. Derived, not downloaded ready-made, so the steps are recorded here:

1. **Source:** *Vignet met een uithangbord van een café*, Rijksmuseum
   RP-P-OB-30.433, dated 1836–1912 — a tavern hanging-sign vignette. Licence
   confirmed **CC0** ("Creative Commons Zero, Public Domain Dedication") from
   the Commons `extmetadata` on 2026-08-05, not inferred from the collection:
   <https://commons.wikimedia.org/wiki/File:Vignet_met_een_uithangbord_van_een_caf%C3%A9_met_daarop_een_kan,_een_kop,_een_fles_en_een_glas,_RP-P-OB-30.433.jpg>
   The bottle and stemmed glass are one cluster inside the larger plate.
2. **Crop** to that cluster (`200x316+1018+679` on the 1956×1595 scan), painting
   out the neighbouring cup, the sign's edge and a stray plate mark.
3. **Threshold and trace** — `mkbitmap -f 6 -s 2 -t 0.48` then
   `potrace -s -u 1 --turdsize 25 --alphamax 1.0 --opttolerance 0.6`. The `-u 1`
   quantisation is what takes it from 55 KB to 22 KB, visually losslessly.
4. **Optimise** with `svgo` at `floatPrecision: 0`, then strip `width`/`height`
   so the viewBox alone sizes it, and set `fill="currentColor"`.

Result is 55 paths — one carrying the bottle, glass and table, the other 54
being ink specks the trace found, since potrace emits one path per disconnected
blob. The `<svg>` payload is ~25 KB raw, ~10 KB gzipped, inlined so the hero
costs no extra request. Note the app sets up no `Rack::Deflater`, so that
gzip figure depends on compression at the edge.

Re-derive rather than hand-edit if it ever needs redoing — tracing is cheap and
the source is stable.

### The app mark

`script/build_brand_icons.py` — the icon set for the Expo client
(`mobile/assets/images/`) and the Rails app's own favicon and apple-touch-icon
(`public/icon.{png,svg}`). Generated, never hand-edited: run the script rather
than opening a PNG.

**Interim.** This replaced the stock Expo template artwork and the Rails
scaffold's red circle, which were blocking store submission and were the live
favicon respectively. It is placeholder-replacement, not a brand exercise — the
real mark is the owner's to choose. The generation is scripted precisely so
that swapping in a different concept later is minutes rather than hours.

The mark is **not new artwork**. It is the lowercase `a` of "aperto" lifted
straight out of EB Garamond at the weight and tracking `.wordmark` already uses
(600, `-0.012em`), set in `--color-ox-2` over a heavy section rule in
`--color-ox-1`, on `--color-paper`. So the icon is the masthead compressed into
a square, and a palette or face change re-derives into a matching icon instead
of drifting away from one. The splash carries the full `aperto.wine` lockup
with `.wine` in `--color-ox-3`, the paper-ground counterpart to the masthead's
soft tone.

A letterform was chosen over the bottle-and-glass engraving deliberately: an
app icon renders at roughly 40–60px in a home-screen grid, and the engraving is
fine 19th-century linework that turns to mush at that size. If a more
distinctive mark is ever wanted, the strongest direction is a **simplified
solid-shape silhouette** derived from the engraving's bottle and glass — it
says "wine" in a way a letter cannot, and unlike the engraving itself it
survives the shrink. Not built; noted so the next person does not re-derive the
reasoning.

#### Provenance

The face is read out of `@expo-google-fonts/eb-garamond`, a pinned dependency
of the Expo client — so `mobile/package-lock.json` fixes exactly which cut of
EB Garamond the outlines came from, and the file is already on disk. Weight 600
is the wordmark's own: `.wordmark` sets `font-weight: 600` and the web app
loads that weight from Google Fonts. The npm package ships every weight, so the
600 file is present regardless of which ones the client bundles — as of #77 it
loads only 400 and 500, and it never renders the mark anyway, which ships as
flat PNG. Nothing is downloaded and nothing is vendored: the outlines are baked
into the output, so nothing at runtime needs the font either.

| | |
|---|---|
| **Face** | EB Garamond SemiBold, Version 1.003, 1000 units/em |
| **File** | `@expo-google-fonts/eb-garamond@0.4.3` → `600SemiBold/EBGaramond_600SemiBold.ttf` |
| **SHA-256** | `32638f825bcb55d6940914fa0c3facdc81ce50d7761463efc46f3b7d1baf619d` |
| **Copyright** | Copyright 2017 The EB Garamond Project Authors, <https://github.com/octaviopardo/EBGaramond12> |
| **Designers** | Georg Duffner and Octavio Pardo |
| **Licence** | **SIL Open Font License 1.1** |

Licence confirmed **from the font binary itself** on 2026-08-18, not inferred
from the package: the TTF's `name` table carries it in nameID 13 ("This Font
Software is licensed under the SIL Open Font License, Version 1.1…") and
nameID 14 (<https://openfontlicense.org>). Corroborated by the package's own
`LICENSE_FONT` file, which reproduces the full OFL 1.1 text under the same 2017
copyright line, and by `package.json`'s `"license": "MIT AND OFL-1.1"` — the
MIT half covers Expo's wrapper code, the OFL half the font.

Baking glyph outlines into the artwork is explicitly permitted and leaves the
result unencumbered. Checked against the OFL FAQ at
<https://openfontlicense.org/ofl-faq/> on 2026-08-18:

- **1.1** — "Can I use the fonts for a book or other print publication, to
  create logos or other graphics or even to manufacture objects based on their
  outlines?" — *"Yes. You are very welcome to do so. Authors of fonts released
  under the OFL allow you to use their font software as such for any kind of
  design work."*
- **1.1.1** — "Does that restrict the license or distribution of that artwork?"
  — *"No. You remain the author and copyright holder of that newly derived
  graphic or object."*
- **1.1.2** — acknowledgement is appreciated but **not required**. This entry
  is the acknowledgement.

The Reserved Font Name provision is closed twice over, so nobody has to
re-derive this. First, **this face declares no RFN at all**: none of the 29
records in the TTF's `name` table mentions one, and nameID 0 is a bare
"Copyright 2017 The EB Garamond Project Authors" with no RFN clause appended
(checked 2026-08-18). The phrase appears in the package's `LICENSE_FONT` only
at line 33, where the OFL *defines* the term — a definition, not a
declaration. Second, and independently: the OFL's RFN and redistribution
conditions bind the *Font Software*, and nothing here redistributes, bundles or
modifies it. The repository contains no font file — only PNG and SVG artwork —
and the generator reads the TTF out of `mobile/node_modules`, which is
gitignored.

```sh
npm install --prefix mobile                          # supplies the font
python3 -m venv /tmp/icons && /tmp/icons/bin/pip install fonttools
/tmp/icons/bin/python script/build_brand_icons.py    # needs imagemagick + librsvg
```

The script asserts what it wrote — every file's dimensions, whether it carries
an alpha channel, and that the art clears the mask circles — because every one
of these is a silent failure:

| File | Constraint | What breaks otherwise |
|---|---|---|
| `icon.png` | 1024², **no alpha channel** | App Store Connect rejects the upload, at the end of a build |
| `android-icon-foreground.png`, `-monochrome.png` | art inside the inner 72/108 circle | the launcher's mask crops the art, differently per device |
| `notification-icon.png` | 96², white on transparency | Android reads only the alpha — a colour icon becomes a solid white square in the status bar |
| `splash-icon.png` | transparent | an opaque image bands its own rectangle across `splash.backgroundColor` |
| `public/icon-maskable.png` | art inside the 80% circle | the PWA manifest's `purpose: "maskable"` entry is cropped |

CI re-asserts the parts of that contract it can see without the generator:
`mobile/__tests__/app-icons.test.ts` decodes each PNG and checks its dimensions,
its colour type, that the transparent layers really are transparent at the
corners, and that the notification silhouette is white wherever it is not
transparent; `test/deploy/brand_icons_test.rb` covers the Rails half — the
manifest renders as JSON, and everything it and the layout name exists. So a
regenerated-wrong asset fails CI rather than a store submission. **Geometry is
not** in CI: only the script knows the intended proportions, so the mask-circle
check runs there and nowhere else.

The PWA manifest itself has no route yet, so `public/icon-maskable.png` is
provisioned ahead of a consumer. It is generated with the marks rather than
later, because the trap it exists to avoid — reusing `icon.png`, whose art
clears the maskable circle by about three pixels — is invisible until someone
enables the manifest and sees a cropped icon.

There is no `android-icon-background.png`: the adaptive background layer is one
flat colour, which `adaptiveIcon.backgroundColor` expresses without shipping a
1024² PNG of it.

## 4. Avoid (attribution required on free tier)

- **Flaticon** (<https://www.flaticon.com>) — free tier requires visible attribution.
- **Vecteezy** (<https://www.vecteezy.com>) — same; filter carefully by license if used.
- **Font Awesome free** — CC BY 4.0, attribution technically embedded but the set
  duplicates what Phosphor already covers.

## Rules of thumb

1. Prefer an existing Phosphor icon, even an approximate one, over adding a new source.
2. When importing, keep the original file name and place it under
   `app/assets/svg/icons/` so the location documents the source library.
3. Only CC0 / MIT / ISC / equivalent no-attribution licenses may be vendored.
   Anything requiring attribution needs explicit sign-off first.
4. Optimize imported SVGs (`npx svgo <file>`) and strip editor metadata.
5. Recolor via `currentColor` / CSS classes, not hardcoded fills, so icons follow
   the theme.
