# Tutar 1.0 (12) Design QA

## Comparison target

- Source visual truth: `/tmp/codex-remote-attachments/019fcb94-a09d-7733-b4cf-9652354138b9/4D19692A-5A84-4381-9585-A848722FD701/2-Fotoğraf-2.jpg` (Dime records screen supplied by the user).
- Previous Tutar state: `/tmp/codex-remote-attachments/019fcb94-a09d-7733-b4cf-9652354138b9/4D19692A-5A84-4381-9585-A848722FD701/1-Fotoğraf-1.jpg`.
- Final implementation: `/tmp/tutar-records-design-12-iphone.png`.
- Full-view comparison evidence: `/tmp/tutar-design-comparison-12.png`.
- Focused summary comparison evidence: `/tmp/tutar-design-hero-comparison-12.png`.
- State: iPhone 17 Pro, iOS 26.5, dark appearance, records tab, seeded transaction data.
- Viewport: 402 × 874 pt at 3×; implementation capture is 1206 × 2622 px.
- Normalization: the 591 × 1280 px source was kept at source density; the implementation was proportionally resized and center-cropped to 591 × 1280 px before comparison.
- The records differ because the source and test build use different data. Layout, hierarchy, typography, contrast, spacing, and interaction placement were compared rather than literal amounts or note text.

## Findings

No actionable P0, P1, or P2 differences remain for the requested direction. Tutar now uses the source screen's clear balance-first hierarchy without reproducing Dime's complete navigation, color treatment, or transaction styling.

Intentional product differences:

- Tutar keeps the visible search field and month arrows for discoverability and the previously requested month navigation.
- Expense and income remain as quiet secondary metrics so the redesign does not remove existing information.
- The trend is monochrome, with no gradient or Dime's turquoise accent.
- The add action remains at the bottom-right, matching the user's earlier reachability requirement rather than Dime's centered tab action.
- Category emoji remain unframed, matching the user's earlier request and keeping Tutar visually distinct.

## Required fidelity surfaces

- Fonts and typography: native San Francisco semantic styles are retained. The net amount is the dominant element, uses tabular digits, scales with Dynamic Type, remains one line at normal sizes, and switches to an accessibility layout at accessibility sizes.
- Spacing and layout rhythm: the month controls, net amount, trend, secondary metrics, section header, and rows form a clear vertical rhythm. All tap targets remain at least 44 × 44 pt. iPhone and iPad layouts were exercised.
- Colors and visual tokens: system background, primary, secondary, separator, and tertiary-fill tokens are used. Dark-mode contrast passed the existing accessibility audit; no gradient or added theme dependency is present.
- Image and icon quality: the screen uses native SF Symbols and the user's category emoji data. No rasterized UI, placeholder icon, handcrafted SVG, or generated decorative asset was introduced.
- Copy and content: `Net toplam` / `Net total` is localized, the selected month uses locale-aware formatting, and the existing localized expense and income labels remain intact.

## Interaction and accessibility evidence

- Previous/next month buttons and horizontal month swipe still change months with animation.
- The bottom-right add control, two-line transaction rows, swipe edit/delete actions, and four tabs remain functional.
- Turkish and English paths, light and dark appearance, standard and accessibility Dynamic Type, and contrast audits were run.
- The final Dynamic Type audit passed after replacing the duplicated fitting header with one conditional semantic layout.

## Comparison history

1. Initial state — P1: the previous Tutar screen gave equal weight to expense, income, and net, so the most useful monthly total lacked a clear focal point. P2: the single-line records were dense and truncated. Fix: introduced a large centered net total, period pill, secondary metrics, and retained the already-fixed two-line records. Evidence: first implementation capture `/tmp/tutar-ui-design-12-first-screens/FFCC3D7C-D101-4F90-A2A6-E604266A48D5.png`.
2. First implementation — P2: the trend stroke was visually heavier than the source and the fitting header produced duplicate Dynamic Type audit findings. Fix: reduced the trend stroke, added a finite chart scale, hid the trend for empty/accessibility states, used `@ScaledMetric`, and replaced `ViewThatFits` with a single conditional semantic layout. Evidence: final implementation and both final comparison images listed above.
3. Final comparison — no actionable P0/P1/P2 issues. The remaining differences are deliberate Tutar product constraints listed above.

final result: passed
