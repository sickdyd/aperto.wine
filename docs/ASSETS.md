# Asset Sourcing Reference

Where to look when a new icon, SVG, or illustration is needed. Check the sources
in order — most needs are covered by what is already vendored in the repo.

## 1. Already in the repo (check first)

### Phosphor icons (full set, vendored)

- **Location:** `app/assets/svg/icons/phosphor/{thin,light,regular,bold,fill,duotone}/`
- **License:** MIT — no attribution required.
- **Rendered via** the `rails_icons` gem (configured in `config/initializers/rails_icons.rb`,
  default library `phosphor`, default variant `regular`, default css `size-5`):

  ```erb
  <%= icon "wine", variant: "regular", css: "size-4 opacity-70" %>
  ```

- Browse names at <https://phosphoricons.com> or `ls app/assets/svg/icons/phosphor/regular/`.
- Wine-relevant icons available: `wine`, `cheers`, `champagne`, `brandy`, `martini`,
  `beer-bottle`.

### Hand-made bottle shapes

- **Location:** `app/views/shared/bottles/` (`_bottle`, `_bordeaux`, `_burgundy`,
  `_champagne`, `_flute`)
- **Rendered via** `bottle_icon(wine, bottle:, size:)` in `app/helpers/wines_helper.rb`.
- Extend these partials for new bottle silhouettes rather than importing external art.

## 2. Cherry-pick from other MIT/ISC icon libraries

For UI icons Phosphor lacks. Copy only the SVGs needed into
`app/assets/svg/icons/<library>/<variant>/` (so `rails_icons` can serve them) and note
the source/license in the commit message. Do **not** add npm/gem dependencies for a
handful of icons.

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
