#!/usr/bin/env bash
# Runs inside the tmux pane: asciinema records Claude Code. Raw timing (no idle
# limit) so the hook's and driver's wall-clock timestamps line up with the cast;
# postprocess.py compresses idle time afterwards.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec asciinema rec --overwrite -q -i 86400 --cols "${COLS:-118}" --rows "${ROWS:-28}" \
  -c "bash '$HERE/agent.sh'" "${DEMO_STATE:?}/raw.cast"
