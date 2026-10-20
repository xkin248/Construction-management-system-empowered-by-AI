---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f3d7249bacac4923999ceda47b8083c_cd7c4540b26c11f19482525400393706
    ReservedCode1: O4AzzxJn7d4EeZ8jAeTrlxFQdlCn2KtAkIFgj1ivrMR/F1hk+48W9e6aOGUzvHfpZyEDK80dIZLeHAGElMO65jbwaUg7fhCVN9/mEdWqgq+WImY0RPwXZKZSjNYT5VkIy9iwlFB5YDvmRyWAXfSwCc0g+uzR+lpwt/yPCvZlRXF5sFh2hwRkCM3yHrM=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f3d7249bacac4923999ceda47b8083c_cd7c4540b26c11f19482525400393706
    ReservedCode2: O4AzzxJn7d4EeZ8jAeTrlxFQdlCn2KtAkIFgj1ivrMR/F1hk+48W9e6aOGUzvHfpZyEDK80dIZLeHAGElMO65jbwaUg7fhCVN9/mEdWqgq+WImY0RPwXZKZSjNYT5VkIy9iwlFB5YDvmRyWAXfSwCc0g+uzR+lpwt/yPCvZlRXF5sFh2hwRkCM3yHrM=
---

# BuildSmart — DESIGN.md

> Design system reference for BuildSmart (Construction Management System Empowered by AI).
> Format follows the [Stitch DESIGN.md spec](https://stitch.withgoogle.com/docs/design-md/specification/) (see awesome-design-md).
> Current implementation lives in `construction_management_system_Flutter/lib/theme/app_theme.dart` (tokens) and `lib/theme/responsive.dart` (breakpoints).
> This file is the single source of truth for how the app should look and feel. Update the token tables below FIRST, then adjust the code to match.

---

## 1. Visual Theme & Atmosphere

**Current direction (as implemented):**
- **Swiss Modernism 2.0** — industrial-gray structure (`#64748B` / `#334155`) with a single **safety-orange** action colour (`#F97316`).
- **Bento-style cards** — sectioned data surfaces with unified 16px radius, hairline borders, soft shadows.
- **Always-dark auth backdrop** — login / worker-register screens are permanently dark (`#0F172A → #1E293B` gradient) regardless of theme mode.
- **Mood:** calm, technical, construction-site honesty. Medium data density, no decoration for decoration's sake.
- **Font:** Inter throughout (Google Fonts, `GoogleFonts.inter`).
- **Both themes:** light (`#F8FAFC` canvas) and dark (`#0F172A` canvas), switchable at runtime via `AppColors.darkMode`.

**Known weakness (why it does not feel modern yet):**
- All radii are locked to a single 16px value → surfaces feel flat, no visual hierarchy between small chips and big cards.
- Shadow system is conservative (single-layer, low alpha) → cards sit *on* the canvas, not *above* it.
- No micro-interactions (hover lift, pressed scale, staggered list entrance).
- No glass / gradient-surface variety on content cards; every card is a plain solid fill.
- KPI/stat displays lack typographic contrast (all values share one weight/size).

**Modernization target (north star):**
`Precise industrial tool · warm premium feel · layered depth · quiet motion` — keep Swiss restraint, add depth, hierarchy and delight without noise.

---

## 2. Color Palette & Roles

Semantic name | Hex (light) | Hex (dark) | Functional role
--- | --- | --- | ---
`accent` (safety orange) | `#F97316` | `#F97316` | Single action colour: primary CTA, active nav, focus ring, brand glow
`accentDark` | `#EA580C` | `#EA580C` | Gradient partner / pressed state of accent
`accentLight` (wash) | `#FFF1E6` | `26% #F97316` | Selected nav pill, accent chip background, icon tile tint
`bgMain` (canvas) | `#F8FAFC` | `#0F172A` | Page background
`bgCard` (surface) | `#FFFFFF` | `#1E293B` | Cards, sheets, app bar, nav bar
`textPrimary` | `#334155` | `#E2E8F0` | Headings, values, primary labels
`textSecondary` | `#64748B` | `#94A3B8` | Body copy, field labels
`textMuted` | `#94A3B8` | `#64748B` | Hints, timestamps, unselected nav
`border` | `#E2E8F0` | `#334155` | Hairline outlines on cards / inputs
`borderLight` | `#F1F5F9` | `#1E293B` | Subtle dividers inside cards
`green` / `greenLight` | `#16A34A` / `#DCFCE7` | `#16A34A` / `29% wash` | Success: present, completed, checked_in, resolved, on_track
`yellow` / `yellowLight` | `#F59E0B` / `#FEF3C7` | `#F59E0B` / `29% wash` | Warning: late, pending, at_risk, in_progress, medium
`red` / `redLight` | `#EF4444` / `#FEE2E2` | `#EF4444` / `29% wash` | Danger: absent, rejected, open, high, critical, delayed
`blue` / `blueLight` | `#2563EB` / `#DBEAFE` | `#2563EB` / `29% wash` | Info: checked_out, low
`purple` / `purpleLight` | `#7C3AED` / `#F3E8FF` | `#7C3AED` / `29% wash` | Secondary info / avatar variety
`onAccent` | `#FFFFFF` | `#FFFFFF` | Text / icons on accent surfaces
`authBgTop / Mid / Bottom` | `#0F172A / #131C2E / #1E293B` | same | Always-dark auth gradient stops

**Rules:**
- One accent only (`#F97316`). Never introduce a second brand colour.
- Status colours are semantic, never decorative.
- Dark-mode "Light" variants use ~16-29% translucent washes of the solid colour (no pale pastels that glare on dark).
- Overlays: `scrim = 30% #000`, `ink = #000000`, on-accent alpha ladder `#FFFFFF → 90/85/70/25/12/6%`.

---

## 3. Typography Rules

**Family:** Inter (Google Fonts). No serif, no mono in UI chrome.

Role | Size | Weight | Line height | Use
--- | --- | --- | --- | ---
`displayLarge` | 34 | 800 | 1.2 | Hero numbers, empty-state titles
`displayMedium` | 26 | 800 | 1.2 | KPI values, page hero values
`headlineLarge` | 24 | 700 | 1.25 | Page titles
`headlineMedium` | 20 | 700 | 1.3 | Section titles
`headlineSmall` / `titleLarge` | 17 | 700 | 1.3 | Card titles, nav section labels
`titleMedium` | 14.5 | 600 | 1.35 | List row titles
`bodyLarge` | 15 | 400 | 1.4 | Default body
`bodyMedium` | 14 | 400 | 1.4 | Secondary body
`bodySmall` | 13 | 400 | 1.4 | Metadata, timestamps
`labelLarge` | 15 | 700 | 1.3 | Buttons
`labelSmall` | 12 | 700 | 0.4 ls | Overline labels
`statusPill` | 12 | 800 | 0.3 ls, UPPERCASE | Status badges (`_` → space)

**Modernization suggestions:**
- Give KPI values more contrast: keep 26/800 but add `tabular figures` feel via Inter; pair with a small uppercase eyebrow label (12/700/letter-spacing 0.8).
- Reserve `displayLarge` for genuine hero moments only — overuse kills hierarchy.

---

## 4. Component Stylings

### Buttons
- **Primary (Elevated):** accent fill `#F97316`, white text, height 50, radius `rBtn` 16, brand gradient optional on hero CTAs (login), disabled = 45% alpha accent. No shadow by default; accent glow (`accent(color, alpha:0.28-0.32, blur:20, dy:8)`) for hero CTAs.
- **Outlined:** transparent fill, 1px `border` stroke, height 50, radius 16.
- **Text button:** accent text, weight 700, no fill.

### Cards (`sectionCard` / `statCard` / `CardTheme`)
- Fill `bgCard`, radius 16 (`rLg`), 1px `border`, shadow `AppShadows.sm` (blur 8, dy 2).
- Card padding default 16. KPI cards: 13/600 label + icon tile (8px padding, 12% accent wash) + 26/800 value + 13 muted sub.

### Inputs
- Filled `bgMain` inside card, radius 16 (`bInput`), 1px `border`; focused = accent 1.6px; hint = `textMuted`; label = `textSecondary`.

### Status pills (`statusPill`)
- Pill radius 999, padding 8/4, uppercase 12/800, background = semantic "Light" wash, text = semantic solid. **Never** outline pills with solid colour borders.

### Navigation
- **Narrow (<700):** Material 3 `NavigationBar`, height 68, bgCard, selected = accent pill on `accentLight` indicator.
- **Wide (≥700):** sidebar 240px, `sidebarBg` slate (`#334155` light / `#0F172A` dark), hover `sidebarHover`, text `#E2E8F0` fixed.

### Feedback
- Toast/snackbar: floating, dark surface `#1E293B`, white text, radius 16, inset 16/12, 2s duration.

---

## 5. Layout Principles

- **Spacing scale:** `4 / 8 / 12 / 16 / 24 / 32` (`AppSpacing`). Card padding = 16, section gaps = 16-24, screen padding = 16 (narrow) / 24 (wide).
- **Max content width:** 1200px on tablet/desktop (`maxContentWidth`); content centered.
- **Density:** comfortable, not cramped; data screens keep 1.3-1.4 line height.
- **Grid:** phone = single column; tablet = 2-column `GridView` for list pages; desktop ≥1024 = wider multi-column where meaningful.
- Whitespace is the primary separator; borders are secondary.

---

## 6. Depth & Elevation

Level | Token | Light | Dark | Used by
--- | --- | --- | --- | ---
1 | `AppShadows.sm` | `4% #0F172A, blur 8, dy 2` | `24% #000, blur 8, dy 2` | Cards, list rows, KPI tiles
2 | `AppShadows.md` | `8% #0F172A, blur 20, dy 8` | `32% #000, blur 20, dy 8` | Floating nav, panels, sheets
3 | `AppShadows.lg` | `10% #0F172A, blur 32, dy 16` | `40% #000, blur 32, dy 16` | Dialogs, hero panels, sticky headers
Hero glow | `AppShadows.accent` | accent 30%, blur 18-26, dy 8-10 | same | Brand logo, primary CTA, hero cards

**Modernization suggestions:**
- Add a 4th "hover" level (sm→md on interaction) and a pressed state (dy drops to 2).
- Dialogs/sheets should feel decisively above content: use `lg` + 16px top radius on sheets.
- Avoid pure-black shadows in light mode — tint with `#0F172A` (slate) as currently done.

---

## 7. Do's and Don'ts

**Do:**
- Use tokens only (`AppColors` / `AppRadius` / `AppShadows` / `AppSpacing`); zero raw `Colors.*` or `Color(0x…)` literals in pages.
- Keep **one** accent. Use status colours only for status semantics.
- Use uppercase + `letterSpacing` for tiny labels and pill text.
- Let whitespace separate; use hairline borders only when grouping is ambiguous.
- Keep dark mode washes translucent (16-29%), never pastel.

**Don't:**
- Don't add a second brand colour or random gradients on content cards.
- Don't use radius >16 on data-dense elements (charts, progress tracks use `hair` 2).
- Don't stack more than 3 elevation levels in one screen.
- Don't use full-bleed saturated colour blocks (construction yellow, safety red) as page backgrounds — reserve them for semantic status only.
- Don't animate layout by rebuilding the Navigator; use the existing `IndexedStack` + `GlobalKey` pattern when switching breakpoints.

---

## 8. Responsive Behavior

- **Breakpoints:** phone `< 600`, tablet `600–1024`, desktop `> 1024` (`AppBreakpoints`).
- **Navigation switch:** `>= 700` → wide sidebar; `< 700` → bottom `NavigationBar`.
- **List pages** (tasks / attendance / workers / projects / worker dashboard): tablet = 2-column grid, phone = single column list; outer `ConstrainedBox(maxWidth: 1200)` centered.
- **Touch targets:** buttons ≥ 50px height; nav bar 68px; list rows comfortable 56-64px.
- **State preservation:** shared singleton `IndexedStack` + `GlobalKey` so pages keep state across breakpoint changes.

---

## 9. Agent Prompt Guide

Quick reference for any coding agent:

> BuildSmart visual identity: Swiss Modernism + industrial restraint. Single safety-orange accent `#F97316` on slate grays. Inter font. Cards = white (light) / `#1E293B` (dark) surface, 16px radius, 1px slate border, soft 8px shadow. Buttons height 50, radius 16. Status pills = uppercase 12/800 on semantic tint. Dark canvas `#0F172A`, light canvas `#F8FAFC`. Content max-width 1200, spacing scale 4/8/12/16/24/32. Breakpoints: phone <600 / tablet 600-1024 / desktop >1024, nav switches at 700. Use tokens from `lib/theme/app_theme.dart`, never hardcode colors. KPI values 26/800 with 13/600 uppercase-ish labels. Keep it calm, precise, quiet motion (150-320ms, easeOutCubic).

Ready-to-use prompts:
- "Redesign the dashboard with bento tiles — use `statCard` with accent icon tiles, add hover elevation, keep KPI values at 26/800."
- "Make the login screen feel premium: keep the dark gradient, add accent glow to the CTA, refine the card shadow to `AppShadows.lg`."
- "Give the tasks list modern polish: staggered entrance (150ms, easeOutCubic), pill statuses, 2-column grid on tablet."

---

## 10. Modernization Roadmap (do these next)

Concrete, low-risk changes to move from "functional tool" to "modern product":

1. **Radius hierarchy** — split `AppRadius` into real tiers: `xs 8 / sm 12 / md 16 / lg 20 / xl 24` (keep `control 14` for buttons/inputs). Cards `lg`, chips `pill`, dialogs `xl`.
2. **Hover / pressed states** — card hover → `AppShadows.md`; button press → scale 0.98 + shadow dy 2; nav item press → subtle indicator grow.
3. **KPI typography** — eyebrow label (11-12 / 700 / ls 0.8 / uppercase) above value; value 28/800 with `FontFeature.tabularFigures()`.
4. **Quiet motion** — page sections fade+slide in on load (150ms stagger); status changes animate color (220ms); pull-to-refresh with accent spinner.
5. **Depth on auth** — login card → `AppShadows.lg` + accent glow at 0.35; fields get focus ring with 2px accent + 12% accent shadow.
6. **Surface variety** — hero/banner tiles may use a subtle gradient (slate `#F1F5F9 → #E2E8F0` light / `#1E293B → #0F172A` dark); keep content cards solid.
7. **Empty & loading states** — add illustrated empty states (icon + 17/700 title + 13 muted hint) and skeleton shimmer instead of bare spinners on list pages.
8. **Consistency pass** — grep for raw `Color(0x` / `Colors.` in `lib/screens`, replace with tokens; verify `flutter analyze` stays 0 issues.

---

## 11. Premium Upgrade Direction（高级感改造方向）

> Target feel: **precise instrument, not a form tool.** Think Linear / Stripe / Vercel / Raycast — quiet colour, sharp typography, layered depth, one focal point per screen. Keep Swiss restraint; remove anything that reads "default Material".

### 11.1 Colour: converge & desaturate

- **Canvas (dark flagship):** deepen to a near-black blue-gray `#0A0E14` (canvas) / `#121821` (surface) / `#1A2230` (elevated). Three-step surface ladder instead of the current two.
- **Canvas (light, optional premium):** warm paper `#F7F7F5`, surface `#FFFFFF`, text `#1A1A1A`, hairline `#E8E6E1` — warmer and calmer than `#F8FAFC` slate.
- **Accent discipline:** keep a single safety orange, but **halve its screen real estate** — default buttons become dark surface (`#121821`) with white text; orange appears only on: primary CTA, active nav indicator, critical status, focus ring, small brand marks. Orange that appears everywhere reads as "warning", not "premium".
- **Status colours, refined:** use deeper, less saturated tones — red `#E5484D`, green `#30A46C`, yellow `#F5A524`, blue `#3E63DD`, purple `#8E4EC6`. Tints at 10-14% opacity, never pastel.
- **Borders:** reduce contrast — hairline `#FFFFFF @ 8%` (dark) / `#0A0E14 @ 6-8%` (light) instead of solid slate `#334155` / `#E2E8F0`. Thinner, quieter, more expensive-looking.

### 11.2 Typography: lighter, tighter, tabular

- Display/headline weights drop from 800 → **600-650**, with **letter-spacing -0.5px** on 20px+ sizes (tightened headlines read premium; bold chunky headlines read casual).
- All numeric values (KPI, dates, durations, progress) use **tabular figures** (`FontFeature.tabularFigures()`).
- KPI layout: 11px / 600 / +0.8px ls / uppercase eyebrow → 28px / 650 / -0.5px ls value → 13px muted delta. Three-line typographic rhythm per stat.
- Buttons: 14px / 600, letter-spacing +0.2px.
- Keep body at 14-15px but set `textSecondary` at 6% lower contrast than today for quieter hierarchy.

### 11.3 Depth & material: layered, not flat

- **Two-part shadows** per elevation: ambient (blur 24, 10-14% `#000`) + key (blur 8, dy 2, 8-10% `#000`) — this dual-shadow recipe is what separates "expensive" cards from "default" ones.
- **Glass surfaces (dark mode):** elevated surfaces (sheets, dialogs, floating bars) use `#121821 @ 72%` + `backdrop blur 20` — glass over content, never over empty canvas.
- **Focus & hover glow:** hover raises elevation one step + border lightens to 14% white; focused inputs get a 1.5px accent ring + 12% accent outer glow.
- Auth screen: login card gets `AppShadows.lg` + accent glow 0.35, gradient backdrop gets a faint radial orange bloom at 4-6% behind the card (already exists at 10% — reduce to 5%, subtlety is the point).

### 11.4 Components: precision details

- **Radius hierarchy:** `xs 8 / sm 12 / md 16 / lg 20 / xl 28`; buttons & inputs 12 (crisper than 16), sheets/dialogs 28 top.
- **Icons:** switch to consistent outlined set (stroke 1.5-1.75px), 20px in bars, 18px in rows, 16px in chips. Mismatched icon weights are the fastest tell of an unpolished UI.
- **Status pills:** 10.5px / 700 / +0.6px ls / uppercase, 6/10 padding, tint 10-14%, radius pill. Lighter weight than the current 800 — quieter.
- **Dividers:** 1px `borderLight` at reduced alpha (6-8%), generous vertical margin — divide by whitespace first, hairline second.
- **Cards:** no gradient fills; solid surface + hairline + dual shadow. Gradient only on brand mark / hero CTA.

### 11.5 Motion: expensive ease

- Durations 220-350ms, curve `easeOutExpo` / `easeOutCubic` — long enough to feel deliberate, fast enough to feel responsive.
- Page sections: fade + 8px rise, 40ms stagger per element.
- Value changes: animated counter (300ms, easeOutExpo). Progress: 400ms animated fill.
- Hover: card raises (shadow md) + border brightens; press: dy → 2, scale 0.985.
- **Never** bounce/spring — springs are playful, this product is precise.

### 11.6 Do not (premium anti-patterns)

- Do not use full-saturation blocks as backgrounds; do not outline cards with `#334155`-class solid borders; do not put orange on every button; do not use w800 headlines; do not use `Curves.bounceOut`; do not fill KPI cards with big icons (small 16px accent tile only).
*（内容由AI生成，仅供参考）*
