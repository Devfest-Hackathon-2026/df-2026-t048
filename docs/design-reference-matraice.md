# MATRAICE Design Contract

Based on https://getdesign.md/notion/design-md, adapted for a dense Japanese B2B KPI application.

## Visual direction

- Warm minimalism: quiet surfaces, clear hierarchy, low decoration.
- B2B density: information may be compact, but should not feel cramped, loud, or toy-like.
- Default UI should be flat: white cards, warm-gray backgrounds, 1px borders, restrained shadows.
- Use dark navy bands for app headers and marketing hero areas only.

## Colors

- Primary CTA: `#5645D4`
- Primary pressed: `#4534B3`
- Primary deep: `#3A2A99`
- On primary: `#FFFFFF`
- Brand navy: `#0A1530`
- Brand navy deep: `#070F24`
- Brand navy mid: `#1A2A52`
- Inline link blue: `#0075DE`
- Inline link pressed: `#005BAB`
- Canvas: `#FFFFFF`
- Surface: `#F6F5F4`
- Surface soft: `#FAFAF9`
- Hairline: `#E5E3DF`
- Hairline soft: `#EDE9E4`
- Hairline strong: `#C8C4BE`
- Text ink: `#1A1A1A`
- Charcoal: `#37352F`
- Secondary text: `#5D5B54`
- Tertiary text: `#787671`
- Soft accent approved by product direction: `#DBEAFE`

## Color rules

- Use purple only for the dominant CTA, active emphasis, and compact badges.
- Do not use purple for body copy or large background areas.
- Use `#0075DE` for inline links; do not use primary purple as a link color.
- Do not reintroduce lavender surfaces. Use `#DBEAFE` or `#EFF6FF` for soft blue accents.
- Do not reintroduce gold/yellow as the product accent unless a specific content warning/banner needs it.

## Typography

- Use the app font stack as Notion-Sans-compatible: `Notion Sans` name first, Inter variable next, Japanese system sans fallback.
- Use Notion-style serif only for display headings and marketing/title moments; dense product headings stay sans for Japanese B2B legibility.
- Body text: 14–16px, weight 400, line-height around 1.5.
- Captions: 12–13px; avoid unreadable 9–10px unless visually compensated.
- Headings: weight 600.
- Buttons: weight 500.
- Avoid heavy `font-black` visual weight; if legacy classes remain, global CSS should normalize them.
- Avoid wide Japanese letter-spacing. Use extra tracking only for short uppercase micro labels.

## Shape and spacing

- Buttons and inputs: 8px radius, 40–44px effective touch height.
- Cards: 12px radius.
- Modals and larger panels: 16px radius.
- Pill radius is allowed only for status badges and tab chips, not normal buttons.
- Use the 4px/8px spacing rhythm. Prefer 12/16/24/32px internal padding depending on density.

## Elevation

- Level 0: no shadow, 1px hairline border. Default for cards and table rows.
- Level 1: subtle `0 1px 2px rgba(15,15,15,.04)`.
- Level 2: restrained `0 4px 12px rgba(15,15,15,.08)`.
- Level 3/4: deep shadows only for hero mockups, modals, and dropdowns.

## Component rules

- Primary button: `#5645D4`, white text, 8px radius, 10px 18px padding.
- Secondary button: transparent/white, `#C8C4BE` border, ink text.
- Dark button: `#0A1530` or black, white text.
- Inputs: white, `#C8C4BE` border, 44px height, purple focus.
- Tables: dense but calm, 1px warm-gray dividers.
- KPI cards: prioritize legibility over decoration; use navy or semantic colors for data, not decorative gradients everywhere.

## Review checklist

- No old gold accent hex values remain.
- No old lavender surfaces remain.
- Purple CTA text is white.
- Inline links are blue.
- Cards are mostly flat with hairline borders.
- Normal buttons are rectangular, not pills.
- Inputs meet 44px height and use purple focus.
- Typography does not rely on 800/900 weights for hierarchy.
- Large display headings use a serif-forward stack; dense app labels remain readable sans.
