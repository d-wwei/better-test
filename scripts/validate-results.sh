#!/bin/bash
# Validate one results.json file with the same rules used by better-test hooks.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_DIR/hooks/lib/common.sh"
. "$REPO_DIR/hooks/lib/rules/results-validation.sh"

if [[ "$#" -ne 1 && "$#" -ne 3 ]]; then
  echo "usage: $0 /path/to/results.json [--profile /canonical/project-profile.json]" >&2
  exit 64
fi

if [[ "$#" -eq 3 ]]; then
  if [[ "$2" != "--profile" || ! -f "$3" ]]; then
    echo "results validation failed: --profile must name an external canonical profile" >&2
    exit 64
  fi
  export BETTER_TEST_TRUSTED_PROFILE="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
fi

RESULTS_FILE="$1"
if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "results validation failed: file does not exist: $RESULTS_FILE" >&2
  exit 66
fi

case "$RESULTS_FILE" in
  /*) ;;
  *) RESULTS_FILE="$(pwd)/$RESULTS_FILE" ;;
esac

if [[ "$(basename "$RESULTS_FILE")" != "results.json" ]]; then
  echo "results validation failed: input file must be named results.json" >&2
  exit 64
fi

OUTPUT=""
RC=0
OUTPUT=$(bt_results_validation_output "$RESULTS_FILE" "$(cat "$RESULTS_FILE")" "$(pwd)" true) || RC=$?

if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$OUTPUT"
fi

exit "$RC"
