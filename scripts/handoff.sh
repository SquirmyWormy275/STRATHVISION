#!/usr/bin/env bash
# Shared handoff tool for Claude Code and Codex. See AGENTS.md.
#
#   scripts/handoff.sh status
#   scripts/handoff.sh claim      <claude|codex> "<what>"        [--force] [--paths p1,p2]
#   scripts/handoff.sh checkpoint <claude|codex> "<done>" "<next>" [--phase "<p>"] [--task "<t>"] [--paths p1,p2]
#   scripts/handoff.sh release    <claude|codex> "<summary>" "<next>" [--paths p1,p2]
#   scripts/handoff.sh note       <claude|codex> "<message>"
#   scripts/handoff.sh heartbeat  <claude|codex> ["<note>"]     # keep-alive for long jobs
#   scripts/handoff.sh processes  <claude|codex> "<desc>"       # record active long-running processes
#   scripts/handoff.sh setup-github           # labels + pinned handoff issue (needs gh auth)
#
# Every write command updates docs/handoff/STATUS.md, commits, pushes, and
# mirrors the entry to the GitHub handoff issue. Network steps degrade to
# warnings, so local state is always written even when offline/unauthenticated.
#
# --paths: comma-separated paths (relative to repo root) to stage instead of
# the whole tree. Always includes STATUS.md. Use this when the other agent
# may have uncommitted work in the shared tree.
set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
STATUS="$ROOT/docs/handoff/STATUS.md"
STALE_MINUTES=30
ISSUE_LABEL="agent-handoff"
ISSUE_TITLE="Agent handoff log (Claude Code <-> Codex)"

die()  { echo "handoff: $*" >&2; exit 1; }
warn() { echo "handoff: warning: $*" >&2; }
now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

check_agent() {
  case "${1:-}" in claude|codex) ;; *) die "agent must be 'claude' or 'codex' (got '${1:-}')";; esac
}

# get_field <name>  -> value from the STATE block
get_field() {
  sed -n '/<!-- STATE:BEGIN -->/,/<!-- STATE:END -->/p' "$STATUS" \
    | sed -n "s/^$1: //p" | head -1
}

# set_fields name=value ...  (values may contain anything but newlines)
set_fields() {
  python3 -I - "$STATUS" "$@" <<'PY'
import re, sys
path, pairs = sys.argv[1], sys.argv[2:]
text = open(path, encoding="utf-8").read()
begin, end = "<!-- STATE:BEGIN -->", "<!-- STATE:END -->"
head, rest = text.split(begin, 1)
block, tail = rest.split(end, 1)
lines = [l for l in block.strip("\n").split("\n") if l.strip()]
for pair in pairs:
    key, value = pair.split("=", 1)
    value = value.replace("\n", " ").strip()
    for i, l in enumerate(lines):
        if l.startswith(key + ":"):
            lines[i] = f"{key}: {value}"
            break
    else:
        lines.append(f"{key}: {value}")
open(path, "w", encoding="utf-8").write(
    head + begin + "\n" + "\n".join(lines) + "\n" + end + tail)
PY
}

# log_entry <agent> <text>  -> prepend under the Log marker
log_entry() {
  python3 -I - "$STATUS" "- $(now) **$1** — $2" <<'PY'
import sys
path, entry = sys.argv[1], sys.argv[2].replace("\n", " ")
marker = "<!-- newest first; scripts/handoff.sh prepends entries below this line -->"
text = open(path, encoding="utf-8").read()
if marker not in text:
    text = text.rstrip("\n") + "\n\n## Log\n\n" + marker + "\n"
text = text.replace(marker, marker + "\n" + entry, 1)
open(path, "w", encoding="utf-8").write(text)
PY
}

minutes_since() {
  local ts="$1" then
  then=$(date -u -d "$ts" +%s 2>/dev/null) || { echo 999999; return; }
  echo $(( ($(date -u +%s) - then) / 60 ))
}

gh_ok() { command -v gh >/dev/null && gh auth status >/dev/null 2>&1; }

issue_number() {
  gh issue list --repo "$(repo_slug)" --label "$ISSUE_LABEL" --state open \
    --json number -q '.[0].number' 2>/dev/null
}

repo_slug() {
  git -C "$ROOT" remote get-url origin \
    | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##'
}

post_issue() {   # post_issue <agent> <markdown>
  gh_ok || { warn "gh not authenticated; skipped GitHub issue update"; return 0; }
  local n; n=$(issue_number)
  [[ -n "$n" ]] || { warn "no open '$ISSUE_LABEL' issue; run: scripts/handoff.sh setup-github"; return 0; }
  gh issue comment "$n" --repo "$(repo_slug)" --body "**$1** · $(now)

$2

<sub>phase: $(get_field phase) · task: $(get_field task) · owner: $(get_field owner) · branch: $(get_field branch)</sub>" >/dev/null \
    || warn "could not comment on issue #$n"
}

# stage_and_commit <message> [paths-csv]
# Always stages STATUS.md. If paths-csv is given, stages only those paths
# (plus STATUS.md). Otherwise stages everything (legacy behaviour).
stage_and_commit() {
  local message="$1"
  local paths_csv="${2:-}"
  cd "$ROOT"
  git add "$STATUS"
  if [[ -n "$paths_csv" ]]; then
    local IFS=','
    for p in $paths_csv; do
      p="${p// /}"
      [[ -n "$p" ]] || continue
      if [[ -e "$p" ]]; then
        git add -- "$p"
      else
        warn "path not found, skipped: $p"
      fi
    done
  else
    git add -A
  fi
  if git diff --cached --quiet; then return 0; fi
  git commit -q -m "$message" || die "commit failed"
  local branch; branch=$(git rev-parse --abbrev-ref HEAD)
  git push -q -u origin "$branch" 2>/dev/null \
    || warn "push failed (not authenticated or offline); commit is local only. Push later with: git push -u origin $branch"
}

sync_first() {
  cd "$ROOT"
  git fetch -q origin 2>/dev/null || { warn "fetch failed; working from local state"; return 0; }
  local branch; branch=$(git rev-parse --abbrev-ref HEAD)
  if git rev-parse -q --verify "origin/$branch" >/dev/null; then
    git merge -q --ff-only "origin/$branch" 2>/dev/null \
      || warn "local branch has diverged from origin/$branch; resolve before trusting STATUS.md"
  fi
}

cmd="${1:-status}"; shift || true
case "$cmd" in
  status)
    sync_first
    sed -n '/<!-- STATE:BEGIN -->/,/<!-- STATE:END -->/p' "$STATUS" | grep -v '<!--'
    hb=$(get_field heartbeat); age=$(minutes_since "$hb")
    echo "heartbeat age: ${age} min (stale after ${STALE_MINUTES})"
    owned=$(get_field owned_paths)
    [[ -n "$owned" ]] && echo "owned paths: $owned"
    procs=$(get_field active_processes)
    [[ -n "$procs" && "$procs" != "none" ]] && echo "active processes: $procs"
    echo "--- recent log"
    sed -n '/prepends entries below this line/,$p' "$STATUS" | sed 1d | head -5
    echo "--- recent commits"
    git -C "$ROOT" log --oneline -5
    if gh_ok && n=$(issue_number) && [[ -n "$n" ]]; then
      echo "--- latest comments on handoff issue #$n (humans may redirect you here)"
      gh issue view "$n" --repo "$(repo_slug)" --comments --json comments \
        -q '.comments[-3:][] | "[\(.createdAt)] \(.author.login): \(.body | split("\n")[0:3] | join(" "))"' 2>/dev/null \
        || warn "could not read issue #$n"
    fi
    ;;

  claim)
    agent="${1:-}"; what="${2:-}"; shift 2 || true
    force=""
    PATHS_CSV=""; EXTRA_FIELDS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --force) force="--force"; shift;;
        --paths) PATHS_CSV="$2"; shift 2;;
        --owned) EXTRA_FIELDS+=("owned_paths=$2"); shift 2;;
        *) die "unknown option $1";;
      esac
    done
    check_agent "$agent"
    [[ -n "$what" ]] || die 'usage: claim <agent> "<what>" [--force] [--paths p1,p2] [--owned path/prefix]'
    sync_first
    owner=$(get_field owner); age=$(minutes_since "$(get_field heartbeat)")
    if [[ "$owner" != "$agent" && "$owner" != "none" && "$age" -lt "$STALE_MINUTES" && "$force" != "--force" ]]; then
      die "$owner holds the work (heartbeat ${age} min ago). Wait until it's ${STALE_MINUTES} min stale, or pass --force if you know $owner is stopped."
    fi
    takeover=""
    [[ "$owner" != "$agent" && "$owner" != "none" ]] && takeover=" (taking over from $owner, last heartbeat ${age} min ago)"
    set_fields "owner=$agent" "heartbeat=$(now)" ${EXTRA_FIELDS[@]+"${EXTRA_FIELDS[@]}"}
    log_entry "$agent" "Claimed: $what$takeover"
    stage_and_commit "handoff($agent): claim — $what" "$PATHS_CSV"
    post_issue "$agent" "🟢 **Claimed**: $what$takeover"
    ;;

  checkpoint)
    agent="${1:-}"; done_="${2:-}"; next="${3:-}"; check_agent "$agent"
    [[ -n "$done_" && -n "$next" ]] || die 'usage: checkpoint <agent> "<done>" "<next>" [--phase P] [--task T] [--paths p1,p2] [--owned path]'
    shift 3
    PATHS_CSV=""; EXTRA_FIELDS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --phase) EXTRA_FIELDS+=("phase=$2"); shift 2;;
        --task)  EXTRA_FIELDS+=("task=$2");  shift 2;;
        --paths) PATHS_CSV="$2"; shift 2;;
        --owned) EXTRA_FIELDS+=("owned_paths=$2"); shift 2;;
        *) die "unknown option $1";;
      esac
    done
    set_fields "owner=$agent" "heartbeat=$(now)" "next=$next" ${EXTRA_FIELDS[@]+"${EXTRA_FIELDS[@]}"}
    log_entry "$agent" "$done_ → next: $next"
    stage_and_commit "checkpoint($agent): $done_" "$PATHS_CSV"
    post_issue "$agent" "✅ **Checkpoint**: $done_

**Next:** $next"
    ;;

  release)
    agent="${1:-}"; summary="${2:-}"; next="${3:-}"; check_agent "$agent"
    [[ -n "$summary" && -n "$next" ]] || die 'usage: release <agent> "<summary>" "<next>" [--paths p1,p2]'
    shift 3
    PATHS_CSV=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --paths) PATHS_CSV="$2"; shift 2;;
        *) die "unknown option $1";;
      esac
    done
    set_fields "owner=none" "heartbeat=$(now)" "next=$next" "owned_paths=" "active_processes=none"
    log_entry "$agent" "Released: $summary → next: $next"
    stage_and_commit "handoff($agent): release — $summary" "$PATHS_CSV"
    post_issue "$agent" "⏸️ **Released**: $summary

**Next:** $next"
    ;;

  note)
    agent="${1:-}"; msg="${2:-}"; check_agent "$agent"
    [[ -n "$msg" ]] || die 'usage: note <agent> "<message>"'
    log_entry "$agent" "Note: $msg"
    stage_and_commit "handoff($agent): note"
    post_issue "$agent" "💬 $msg"
    ;;

  heartbeat)
    agent="${1:-}"; note="${2:-}"; check_agent "$agent"
    set_fields "owner=$agent" "heartbeat=$(now)"
    if [[ -n "$note" ]]; then
      log_entry "$agent" "Heartbeat: $note"
      stage_and_commit "handoff($agent): heartbeat"
      post_issue "$agent" "💓 $note"
    else
      # silent heartbeat: only update timestamp, still commit STATUS.md
      stage_and_commit "handoff($agent): heartbeat"
    fi
    ;;

  processes)
    agent="${1:-}"; desc="${2:-}"; check_agent "$agent"
    [[ -n "$desc" ]] || die 'usage: processes <agent> "<description of active long-running jobs>"'
    set_fields "owner=$agent" "heartbeat=$(now)" "active_processes=$desc"
    log_entry "$agent" "Active processes: $desc"
    stage_and_commit "handoff($agent): processes"
    post_issue "$agent" "⚙️ **Active processes**: $desc"
    ;;

  setup-github)
    gh_ok || die "gh is not authenticated. Run: gh auth login"
    slug=$(repo_slug)
    gh label create "$ISSUE_LABEL" --repo "$slug" --color 5319e7 \
      --description "Claude Code <-> Codex handoff log" --force >/dev/null
    for a in claude codex; do
      gh label create "agent:$a" --repo "$slug" --color 0e8a16 --force >/dev/null
    done
    n=$(issue_number)
    if [[ -z "$n" ]]; then
      url=$(gh issue create --repo "$slug" --title "$ISSUE_TITLE" --label "$ISSUE_LABEL" --body \
"Live handoff channel between **Claude Code** and **Codex**. Both agents post claims, checkpoints, releases, and notes here through \`scripts/handoff.sh\`.

- Source of truth: [\`docs/handoff/STATUS.md\`](../blob/implementation/docs/handoff/STATUS.md) on the \`implementation\` branch, plus \`git log\`.
- Protocol: [\`AGENTS.md\`](../blob/implementation/AGENTS.md).
- Humans: comment here to redirect either agent. Agents read this thread when they start a session.")
      n=${url##*/}
      gh issue pin "$n" --repo "$slug" >/dev/null 2>&1 || warn "could not pin issue #$n"
    fi
    echo "handoff issue: #$n  https://github.com/$slug/issues/$n"
    ;;

  *) die "unknown command '$cmd' (status|claim|checkpoint|release|note|heartbeat|processes|setup-github)";;
esac
