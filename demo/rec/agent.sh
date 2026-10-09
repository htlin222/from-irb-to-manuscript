#!/usr/bin/env bash
# The inner Claude Code session that gets recorded. Started ONCE; every chapter
# is the next message in the same conversation (no /exit between chapters).
#
# --setting-sources project,local  the viewer sees the project's rules, not the
#                                  recorder's personal ~/.claude setup
# --settings session-settings.json Stop hook (records when each turn ends) + light theme
# --mcp-config mcp.json            OpenEvidence for the literature chapter
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Drop the parent session's identity so the inner one starts clean.
for v in $(env | grep -oE '^(CLAUDE[A-Z_]*|AI_AGENT)=' | tr -d '='); do
  [ "$v" = CLAUDE_CODE_NO_FLICKER ] || unset "$v"
done
export DEMO_STATE="${DEMO_STATE:?}" DEMO_HOME="$HERE/.." DEMO_STAGES="${DEMO_STAGES:-$HERE/../stages.toml}"
export IS_SANDBOX=1
exec claude --model opus --effort high --dangerously-skip-permissions \
  --setting-sources project,local \
  --settings "$HERE/session-settings.json" \
  --mcp-config "$HERE/mcp.json" \
  -n "her2-neoadjuvant-study"
