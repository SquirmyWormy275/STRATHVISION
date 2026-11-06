# Agent Instructions (Claude Code and Codex)

Two coding agents work on this repo: **Claude Code** and **Codex**. Either one can be stopped at any moment by a rate limit. These rules let the other one pick up with nothing lost.

## Start of every session

1. `git pull --rebase` (or `git fetch && git status` if you have local work).
2. Run `scripts/handoff.sh status` and read `docs/handoff/STATUS.md` from top to bottom.
3. Read `git log --oneline -15`. **Commits are the ground truth.** If STATUS.md and the code disagree, trust the code and correct STATUS.md.
4. Claim the work: `scripts/handoff.sh claim <claude|codex> "<what you are picking up>"`.
   - If STATUS.md shows the other agent as owner with a heartbeat under **30 minutes** old, do not take over. That agent is probably still working. Pick an unrelated task or stop.
   - If the heartbeat is older than 30 minutes, assume the other agent hit a rate limit. Take over and say so in the claim message.

## While working

- **Checkpoint after every finished task or meaningful step:** `scripts/handoff.sh checkpoint <agent> "<what is done>" "<exact next step>"`. This commits only the status update by default. To include completed work, append `--paths path/to/file another/file` (last option); directories include all changes beneath them. Unrelated staged work is preserved. Pushing requires `HANDOFF_PUSH=1`; issue comments require `HANDOFF_POST_ISSUE=1` and user authorization to send them.
- You may be cut off at any moment, with no chance to write a final note. Your last checkpoint is your handoff, so keep it current.
- Write the next step so a stranger can do it: file paths, command, expected result.
- Never leave the branch broken across a checkpoint. If you're mid-change, checkpoint as `WIP:` with the exact failing test or step.

Refresh ownership during long work with `scripts/handoff.sh heartbeat <agent>`; this makes no commit or network request. `status` is read-only by default; `HANDOFF_SYNC=1` enables fetch/fast-forward and `HANDOFF_READ_ISSUE=1` reads issue comments. Status/release never sweep up unrelated files.

## Stopping on purpose

`scripts/handoff.sh release <agent> "<summary>" "<next step>"` clears the owner so the other agent can start immediately.

## Asking the other agent or the human

- `scripts/handoff.sh note <agent> "<message>"` appends to the local log. External comments are opt-in as above.
- Open questions for the human go under **Blockers** in STATUS.md. Follow the "stop and ask" rule in `docs/EXECUTION_PLAN.md`. Do not invent behavior to get past a blocker.

## Project rules (binding)

- Follow `docs/EXECUTION_PLAN.md` in order. Do not start a task until the previous one meets its acceptance criteria.
- `docs/DECISIONS.md`, `docs/INTERFACES.md`, `docs/ARCHITECTURE.md` and `docs/CARNE_ASADA.md` are binding contracts. Do not invent features outside them.
- Every acceptance criterion gets automated tests where feasible.
- Work on the `implementation` branch. Do not push to `main` without the human.

## App commands

See `apps/strathvision/README.md`. In short:

```sh
cd apps/strathvision
flutter pub get && dart run build_runner build -d
flutter analyze && flutter test
```

Drift widget tests: finish each `testWidgets` by unmounting the app and pumping `Duration.zero`, or the test hangs on Drift's stream-close timer (see `test/widget_test.dart`).
