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
