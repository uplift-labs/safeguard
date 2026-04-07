#!/bin/bash
# no-push-to-main.sh — Safeguard Guard
# Escalates git push to main/master to user approval with diff context.
# Input: JSON on stdin. Output: ASK:<reason> | empty (allow).

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

CMD=$(json_field "command" "$INPUT")
[ -z "$CMD" ] && exit 0

# Only check git push commands
case "$CMD" in
  *git\ push*|*git\ \ push*) ;;
  *) exit 0 ;;
esac

PUSHING_TO_MAIN=false
TARGET_BRANCH=""

# Explicit: git push <remote> main/master
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(^|[^[:alnum:]_/])(main|master)([^[:alnum:]_]|$)'; then
  PUSHING_TO_MAIN=true
  TARGET_BRANCH=$(printf '%s' "$CMD" | grep -oE '(^|[^[:alnum:]_/])(main|master)([^[:alnum:]_]|$)' | grep -oE '(main|master)' | head -1)
fi

# Refspec: git push origin HEAD:main or HEAD:refs/heads/main
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*HEAD:(refs/heads/)?(main|master)'; then
  PUSHING_TO_MAIN=true
  TARGET_BRANCH=$(printf '%s' "$CMD" | grep -oE '(main|master)' | tail -1)
fi

# Bare push — check if current branch is main/master
if [ "$PUSHING_TO_MAIN" = false ]; then
  if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]*$|git[[:space:]]+push[[:space:]]+-[a-zA-Z]*[[:space:]]*$|git[[:space:]]+push[[:space:]]+[a-z]+[[:space:]]*$'; then
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
    case "$CURRENT_BRANCH" in
      main|master)
        PUSHING_TO_MAIN=true
        TARGET_BRANCH="$CURRENT_BRANCH"
        ;;
    esac
  fi
fi

[ "$PUSHING_TO_MAIN" = false ] && exit 0

# Build diff context for user decision
CONTEXT="PUSH TO $TARGET_BRANCH DETECTED"

COMMITS=$(git log --oneline "origin/$TARGET_BRANCH..$TARGET_BRANCH" 2>/dev/null | head -20)
if [ -n "$COMMITS" ]; then
  COMMIT_COUNT=$(printf '%s\n' "$COMMITS" | wc -l | tr -d ' ')
  CONTEXT="$CONTEXT | $COMMIT_COUNT commit(s)"
else
  CONTEXT="$CONTEXT | (could not determine commits)"
fi

STATS=$(git diff --stat "origin/$TARGET_BRANCH..$TARGET_BRANCH" 2>/dev/null | tail -1)
[ -n "$STATS" ] && CONTEXT="$CONTEXT | $STATS"

# GitHub compare URL (if remote is GitHub)
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
case "$REMOTE_URL" in
  *github.com*)
    REPO_PATH=$(printf '%s' "$REMOTE_URL" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
    if [ -n "$REPO_PATH" ]; then
      HEAD_SHA=$(git rev-parse --short "origin/$TARGET_BRANCH" 2>/dev/null)
      CONTEXT="$CONTEXT | Compare: https://github.com/$REPO_PATH/compare/$HEAD_SHA...$TARGET_BRANCH"
    fi
    ;;
esac

[ -n "$COMMITS" ] && CONTEXT="$CONTEXT -- Commits: $COMMITS"

printf 'ASK:[safeguard:no-push-to-main] %s' "$CONTEXT"
exit 0
