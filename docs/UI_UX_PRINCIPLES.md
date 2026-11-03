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
