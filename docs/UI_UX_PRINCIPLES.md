# STRATHVISION UI/UX Principles

Binding. The backend can be as sophisticated as required. The surface cannot.

## Core Contract

- Usable by someone who is reluctant to touch a phone and who already finds OnForm difficult. Coaches’ job is to convey movement, not operate software.
- Coach and athlete should feel they are only coaching or reviewing the human subject. They remain blissfully unaware of densities, reinforcement learning, importance weights, and parameter updates.
- Every interaction should feel like reviewing video.

## Design Feel

- Clean, calm, precise. Animations short and purposeful.
- Feels like an advanced tool that stays out of the way.
- No clutter, no feature walls, no setup rituals.
- Preserve and improve the useful OnForm primitives (dual video, sync, slow-mo, mirror). Everything else is optional.

## Progressive Enhancement

Layers work independently and stack:

1. Just footage — dual or single video, playback, sync, slow-mo, mirror. Already useful.
2. Per-stroke stepping + simple red/green. Model improves.
3. Voice notes or walkthroughs. Model improves more.
4. Incoming coach marks and notes. Model improves further.

No layer is required. Additional clean footage alone produces recursive improvement. Deep review is available and never mandatory. No one should need twenty minutes of marking to receive value.

## Interaction Rules

- Recovery from mistakes is instant and obvious (one-tap undo or equivalent that always works).
- The current stroke and current attribute are unmistakable without relying on memory or text-heavy labels.
- Defaults are aggressively good. Most users never open settings.
- Controls (red/green, boundary drag, sync, record) respond on the frame they are touched. Backend latency is acceptable; control latency is not.
- Empty and partial states (below Good, missing implement, single video, no coach package) look finished and useful, not disabled.
- One primary action per screen.
- Layout consistency supports spatial memory (big video left, mark controls bottom-right, stepper under video, etc.).

## Aha Standard

The model should surface real subtle patterns that experienced coaches and competitors already see—spacing that avoids overlap, opening/closing motions, small hinge or path changes—before anyone has named or tagged them.

When it does so correctly and the user recognizes “it caught that,” the tool feels like magic. Present the difference cleanly (overlay, ghost, ranked delta). No invented labels or coaching language. The recognition comes from the user.

Self-learning from additional clean footage is what makes those unnamed distinctions appear and sharpen.

## Frontend Quality Bar (mandatory for implementation)

- Production-grade, component-driven UI. Not static HTML, not a thin wrapper around video tags, not a WebView.
- Flutter is the cross-platform target (iOS, Android, desktop). Implementation must use Flutter’s full widget and composition model, custom painters for overlays, ghosts, and paths, and proper state management.
- Visual standard: tight typography, consistent spacing system, restrained motion, high-contrast mark controls, video-first layouts that feel like dedicated pro training / sports-analysis software.
- Dual-video surfaces, stroke steppers, re-projected ghosts, and path overlays are first-class rendered elements.
- Same UI shell serves timber, Olympic lifting, and other packs; sport-specific controls are data-driven additions inside the existing layout.
- Performance requirement: 60 fps scrubbing and immediate control response while pose and implement overlays are active. Jank is a defect.
- Empty, loading, and below-threshold states are fully designed screens.

Coding agents must treat the frontend as a primary deliverable equal in importance to the engine. Basic HTML, minimal scaffolding, or placeholder UIs do not meet this bar.

## Empty and Partial States — Quiet Intelligence

These states are fully designed and screenshot-worthy. They communicate that capable work is occurring behind the scenes without requiring user action or explanation. Motion is restrained, geometric, and optional (can be disabled).

- Visual language: generous space, clean lines, slow breathing outlines, faint traveling highlights on timelines or stroke segments, soft pulses on progress marks. Single accent color used only on living elements. No conventional spinners or chore-like progress bars.
- Below Good: complete base review tools present. Delicate animated trace on already-detected strokes; usable-time indicator has a soft living underline. Feeling of “already studying,” not “features missing.”
- Implement untracked: body skeleton appears cleanly; faint expected path yields after a moment.
- Model update or fit completing: brief elegant sweep or ghost re-draw, then silence. No mandatory toast.
- True empty library: calm drop target with slow pulse that resolves into stroke highlights on first clip.
- Single-video, no-coach, and sync-pending states remain finished and quiet; advanced controls omitted rather than disabled.

The goal is understated wonder: the user senses intelligence and occasional sharpness without ever managing the backend. This is a primary differentiator of the product.

## Send / Receive

Single clean sheet launched from the review screen.

- Three large, equal targets (shown only when available):
  - Code / QR — generated immediately, large type, copy or display.
  - System Share sheet (Messages, WhatsApp, etc.).
  - Folder — only if a paired inbox already exists; otherwise omitted.
- Incoming coach returns appear as a quiet badge or notification. Opening the return applies the light update, plays the brief elegant sweep, and restores the user to the same stroke.
- Language is limited to “Send to coach” and “Coach notes arrived.” No account creation, no sync jargon, no status dashboards.

The flow must feel as light as handing someone a phone.

## Library / Home

A single calm filmstrip control panel. The file system and the control surface are the same object.

- Full-width horizontal filmstrip is the only primary content. Most recent session is largest. Thumbnails are pure video frames.
- Restrained living underline (same language as partial-state stroke traces) appears only when the system has already detected strokes or applied an update. No badges, percentages, or competing icons.
- Tap any thumbnail opens review immediately, landed on the last-viewed stroke if one exists.
- Active overlay name is a quiet top-left wordmark; tap to switch. It does not resemble a menu until touched.
- Add footage is a slim “+” at the leading edge of the filmstrip itself.
- Incoming coach notes: the relevant thumbnail receives the brief elegant sweep, then keeps a faint accent edge until opened (opening applies the light update and clears the edge).
- Earlier clips continue on the same strip and simply become smaller and quieter. No secondary “see all” screen.
- Empty state: the filmstrip region is the calm pulsing drop target; the first clip resolves the pulse into the underline.
- All secondary actions (export, settings, packages, gesture mapper) live one level down and are invisible here.

The home screen’s only job is to place the next footage under the thumb. It looks finished and quietly alive even when nearly empty, and never asks the user to manage files, models, or status.

## Vibe-Coded Smells to Avoid

Drawn from the YC Design Review critiques of AI-generated interfaces. These patterns make a product feel generic, frustrating, or unfinished. They are forbidden in STRATHVISION.

- Cryptic or unlabeled primary actions. Buttons must say what they do by position, color, and clear short text. No mystery labels.
- Extra clicks or reveals before the main verb. The action the user came to perform is visible and one step away.
- Fake interactivity. Anything that looks tappable must respond immediately. No decorative controls.
- Scroll-jacking or forced pacing. The user controls the timeline and filmstrip. No hijacked scroll, no auto-advancing tabs or steppers.
- Decorative motion. Animation exists only to signal real system state (stroke detected, update applied, recording live). Glows, random pulses, and flourish are out.
- Model-default typography and styling (Instrument Serif, Space Grotesk, generic gradients, random bolding, em-dash spam). Typography, spacing, and accent are chosen once and locked.
- Tiny, angled, or low-contrast critical text. Usable-time marks, attribute names, and CTAs must be readable at a glance.
- Investor or internal language on user-facing surfaces. Speak only about the footage and the marks.
- Dense, fast, or auto-playing demos that hide the point. Show one clear thing.
- Progress or status that feels like a chore. Quiet living underlines and brief sweeps only.

Positive patterns to keep: motion that reinforces a real change, generous spacing, immediate obvious actions, and visual calm that still signals intelligence.

## Attribute and Priority Chips

The control that selects what is being graded. It must feel like part of video review.

- Thin horizontal chip row. Appears in marking mode, or remains quietly present once the Good threshold is reached.
- Last-used priorities are pre-loaded. The most recent or most-greened attribute is visually current.
- Tap a chip to make it active; red/green then apply only to that attribute on the current stroke. Long-press or a small “+” adds another attribute from the pack’s short predefined list. No free-text entry on the phone.
- Switching chips does not move the playhead or change the current stroke.
- Active chip uses the same restrained accent as the living underlines. Inactive chips stay low-contrast.
- On first use or when empty, the row simply offers the pack’s top 3–4 attributes. No tutorial modal or explanation.

The user grades the movement. They never configure a model.

## Progress / Trend View

Optional surface for parameter history. Must not appear on primary paths.

- Reached only by long-press on an attribute chip or via a secondary “Progress” entry one level down from library or review. Never present on the main review screen or filmstrip.
- Displays a single calm sparkline or simple residual comparison for the selected attribute across recent prioritized sessions.
- Generated exclusively from the already-stored per-attribute parameter history (μ and residuals). No video is re-processed.
- Language is strictly observational: “Closer on the last four sessions you marked.” No advice, no coaching voice, no percentages unless the user explicitly expands.
- Dismiss returns the user to the exact stroke and playhead they left.

This is the only place the evolving model becomes quietly visible. Daily use never requires it.

## Package Export Sheet

Plain-language sharing surface. Must make the contents obvious before anything leaves the device.

- Reached from secondary actions (one level down) or by long-press on an overlay name.
- Displays the coach and event name large, followed by three explicit choices:
  1. Coaching profile only (default) — “Just the model. No notes or marks.”
  2. Coaching profile + my marks — “Includes the grades you gave.”
  3. Full local overlay — “Everything for this coach and event.”
- A single sentence states exactly what is included and what is stripped before the package is written.
- One large export button. The resulting package is handed to the existing code / QR, system share sheet, or folder paths.
- Version identifiers, hashes, and internal IDs remain hidden unless the user expands a “Details” disclosure.

Sharing feels like choosing what to hand someone, not like managing a model file.
