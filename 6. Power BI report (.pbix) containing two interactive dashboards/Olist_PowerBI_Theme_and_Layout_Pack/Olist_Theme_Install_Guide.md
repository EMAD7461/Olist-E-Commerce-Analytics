# Olist Executive Dashboard Theme

## Import
1. Open Power BI Desktop.
2. View > Themes > Browse for themes.
3. Select `Olist_Executive_Theme.json`.
4. Existing visuals may retain explicit formatting overrides; inspect them after import.

## Important limitation
A Power BI theme JSON controls supported visual defaults (colors, fonts, titles, labels, backgrounds). It does NOT create the page layout, add visuals, place objects at exact coordinates, set all visual-specific settings consistently, or guarantee pixel-perfect reproduction of a reference image. To reproduce the image closely, manually build/position visuals or edit a PBIP report definition using a compatible Power BI report-layout workflow.

## Design tokens
- Canvas: #F3F7FD
- Navy: #102A66 / #12327A
- Primary blue: #1554D1
- Accent cyan: #12B8D5
- Success green: #27A879
- Warning amber: #FFB52E
- Alert coral: #FF6B62
- Font: Segoe UI / Segoe UI Semibold
- Suggested canvas: 16:9, 1280 × 720 (or 1920 × 1080 for high-resolution design work)

## Suggested visual sizing (for a 16:9 page)
- Left navigation: 14% width.
- Header/title and slicers: 9–11% height.
- KPI cards: 14–16% height.
- Main charts: 25–28% height.
- Secondary charts: 25–28% height.
- Bottom detail row: 18–20% height.

Use these as a starting grid only; exact placement depends on page size and the visuals available in your Power BI version.
