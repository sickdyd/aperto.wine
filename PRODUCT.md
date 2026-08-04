# Product

## Register

product

## Users

- **Restaurant owners** managing their venue's digital wine lists: creating restaurants, wines, wine lists, and per-table QR codes from an admin area. Usually working from a laptop between services; task-focused, not browsing.
- **Diners** who scan a table QR code and browse the restaurant's wine menu on their phone.

## Product Purpose

aperto.wine turns a restaurant's wine cellar into a digital, QR-accessible wine list. Owners manage wines, lists, tables, and orders; guests scan a per-table QR to view the menu and order. Success = owners can maintain their list quickly and guests get an elegant, legible menu.

## Brand Personality

**The Sommelier's Ledger** — a printed wine ledger rather than a web app. Print typography throughout: Instrument Serif for display, EB Garamond for body and menu copy, JetBrains Mono for labels, data and prices.

Oxblood is structure, not accent: a five-step ramp carries the rules, headings, prices, masthead and primary actions, while black ink is reserved for body copy. Grounds are warm paper stocks — three of them, for tonal stacking — carrying a perceptible paper grain. Depth comes from stock and overlap, never from elevation.

Rules replace boxes: hairline for row division, medium for subsection, heavy for section break. Leader dots — a dotted rule running from a label to its right-aligned value — are the signature detail. **Zero border radius, no drop shadows anywhere.**

The public menu carries the brand at full expression: display type at scale, the engraved bottle-and-glass pour, generous rhythm. The owner admin area holds the same vocabulary quiet — no display type in labels or buttons, no illustration, denser rhythm, oxblood for structure and emphasis only.

## Anti-references

- Generic SaaS dashboard chrome (gradient heroes, stat-card grids).
- Over-decorated admin UI — display fonts in labels/buttons, decorative motion.
- Dark "tech" aesthetics; this is hospitality, not devtools.

## Design Principles

1. **The admin disappears into the task** — familiar controls, consistent form vocabulary, no surprises.
2. **One component vocabulary** — same field, label, button, and section treatment on every screen (daisyUI 5 + shared component classes).
3. **Brand lives in the menu, restraint lives in the admin.**
4. **Mobile-first for diners, desktop-comfortable for owners.**

## Accessibility & Inclusion

WCAG 2.1 AA target: ≥4.5:1 body/label contrast, visible focus states, proper label/input association, reduced-motion respected. Public menu must work well on small phones in dim restaurant lighting.
