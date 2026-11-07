# STRATHVISION visual system — footage first

User-authorized implementation direction, November 7, 2026. This is a specification, not proof of device/performance acceptance. See [handoff](handoff/UI_REDESIGN.md).

## Identity

Local-first athletic video review. Compare movement with an explicit reference, not a universal technique grade. Flutter/Dart and sport-pack boundaries remain intact. Models, packages and research are not the home screen.

| Token | Hex | Role |
|---|---|---|
| Chalk | #F4F3EF | Light canvas |
| Graphite | #111416 | Dark canvas / video surround |
| Slate | #20262B | Dark supporting surface |
| Ink | #182025 | Light text |
| Soft white | #F5F4F0 | Dark text / primary-action label |
| Cobalt | #315DDF | Action / selection |
| Pale cobalt | #91AEFF | Dark accent text |
| Good | #247A46 | Human positive mark + check |
| Needs work | #B83A36 | Human negative mark + cross |

Barlow Semi Condensed: short headings and wordmark. Source Sans 3: controls, body, measurements. Tabular figures for time/numbers. Body/control text 16 logical pixels, secondary 14; controls at least 48, mark buttons 56. Radii: controls 8, video 12, sheets 16. One geometry in light/dark. No gradients, glows or per-screen accent inventions.

`python scripts/fetch_ui_fonts.py` retrieves pinned upstream Git blobs and both OFL notices before building. Flutter bundles the result. No runtime font service or system-font redistribution.

## Layout and behavior

The home is a horizontal lazy filmstrip over existing Projects. Most recently visited is prominent; earlier reviews stay on the same strip. Add clip opens the picker directly; cancellation stores no project. Profiles, package exchange and workbench remain one level down. No account, Favorites/Tags subsystem, social feed, dashboard sidebar or redundant Open latest button.

One loaded video gets the canvas. Compare adds another; Single view hides a stage without deleting feedback or footage. Source frames use contain in review, not aesthetic cropping. Axis follows available space/aspect ratios; player lifetime is route-scoped. Undo stays visible. Short windows and enlarged text scroll rather than overflow.

Analysis is optional, as a wide inspector or dismissible narrow detail surface. Long inference never holds the transport-operation lock. Profiles restore exact versions, including explicit measurements-only. Coverage warnings remain visible.

## Truthful visual language

Red/green are human judgments on the selected attribute, never automatic grades or start/contact markers. The generated mockup's 87%, hip/path conclusions, timing conversions and More forward lean cue are not application requirements or real data. No ghost or path control without a supported result. No animation implying unperformed learning.

The four generated references in the supplied handover are concepts, not screenshots of the implementation. Rendered Flutter candidates must disclose fake players/measurements. Native screenshots, physical devices and coaching validity are separate evidence categories.
