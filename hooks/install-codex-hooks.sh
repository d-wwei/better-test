#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REGISTRY_FILE="$SCRIPT_DIR/registry.json"
. "$SCRIPT_DIR/lib/common.sh"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"
MANAGED_PREFIX="better-test:"
COMMAND_ROOT="$SKILL_ROOT/hooks/codex/"

COMMAND="${1:-install}"
shift || true

PROJECT_ROOT=""
ENABLE_FEATURE_FLAG=false
HOOK_FEATURE_KEY="hooks"

if command -v codex >/dev/null 2>&1; then
  if codex features list 2>/dev/null | awk '$1 == "hooks" { found=1 } END { exit found ? 0 : 1 }'; then
    HOOK_FEATURE_KEY="hooks"
  elif codex features list 2>/dev/null | awk '$1 == "codex_hooks" { found=1 } END { exit found ? 0 : 1 }'; then
    HOOK_FEATURE_KEY="codex_hooks"
  fi
fi

usage() {
  cat <<'USAGE'
Usage:
  hooks/install-codex-hooks.sh install [--project <path>] [--enable-feature-flag]
  hooks/install-codex-hooks.sh status [--project <path>]
  hooks/install-codex-hooks.sh uninstall [--project <path>]
USAGE
}

resolve_project_root() {
  local requested="${1:-}"

  if [[ -n "$requested" ]]; then
    (
      cd "$requested" 2>/dev/null || exit 1
      pwd
    )
    return
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return
  fi

  pwd
}

has_feature_flag() {
  if [[ -f "$CONFIG_FILE" ]] && awk '
      /^\[features\][[:space:]]*$/ { in_features=1; next }
      /^\[/ { in_features=0 }
      in_features && /^[[:space:]]*(hooks|codex_hooks)[[:space:]]*=[[:space:]]*true([[:space:]]|$)/ { found=1 }
      END { exit found ? 0 : 1 }
    ' "$CONFIG_FILE"; then
    return 0
  fi

  command -v codex >/dev/null 2>&1 || return 1
  codex features list 2>/dev/null | awk -v key="$HOOK_FEATURE_KEY" '
    $1 == key && $NF == "true" { found=1 }
    END { exit found ? 0 : 1 }
  '
}

enable_feature_flag() {
  local backup_file
  local temp_file

  mkdir -p "$CODEX_HOME"
  backup_file="$CONFIG_FILE.backup-$(date +%Y%m%d%H%M%S)"
  temp_file="$(mktemp)"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$temp_file" <<EOF
[features]
${HOOK_FEATURE_KEY} = true
EOF
    mv "$temp_file" "$CONFIG_FILE"
    echo "enabled $HOOK_FEATURE_KEY in $CONFIG_FILE"
    return
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$backup_file"
  fi

  awk -v hook_key="$HOOK_FEATURE_KEY" '
    BEGIN {
      saw_features = 0
      in_features = 0
      inserted = 0
    }
    /^\[features\][[:space:]]*$/ {
      saw_features = 1
      in_features = 1
      print
      next
    }
    /^\[/ {
      if (in_features && !inserted) {
        print hook_key " = true"
        inserted = 1
      }
      in_features = 0
      print
      next
    }
    {
      if (in_features && /^[[:space:]]*(hooks|codex_hooks)[[:space:]]*=/) {
        if (!inserted) {
          print hook_key " = true"
          inserted = 1
        }
        next
      }
      print
    }
    END {
      if (!saw_features) {
        if (NR > 0) {
          print ""
        }
        print "[features]"
        print hook_key " = true"
      } else if (in_features && !inserted) {
        print hook_key " = true"
      }
    }
  ' "$CONFIG_FILE" 2>/dev/null > "$temp_file"

  mv "$temp_file" "$CONFIG_FILE"
  printf 'enabled %s in %s' "$HOOK_FEATURE_KEY" "$CONFIG_FILE"
  if [[ -f "$backup_file" ]]; then
    printf ' (backup: %s)' "$backup_file"
  fi
  printf '\n'
}

list_registry_bindings() {
  jq -r '
    .hooks[]
    | . as $hook
    | (
        if (($hook.platforms.codex.bindings // []) | length) > 0 then
          $hook.platforms.codex.bindings[]
        elif ($hook.platforms.codex.status // empty) != "" then
          {
            status: $hook.platforms.codex.status,
            event: $hook.platforms.codex.event,
            matcher: $hook.platforms.codex.matcher,
            entrypoint: $hook.platforms.codex.entrypoint,
            note: ($hook.platforms.codex.note // "")
          }
        else
          empty
        end
      )
    | [
        $hook.id,
        (.status // $hook.platforms.codex.status // ""),
        (.event // ""),
        (.matcher // ""),
        (.entrypoint // ""),
        ($hook.rule_path // ""),
        (.note // $hook.platforms.codex.note // "")
      ]
    | @tsv
  ' "$REGISTRY_FILE"
}

validate_active_entries() {
  local missing=0
  local id status event matcher entrypoint rule_path note

  while IFS=$'\t' read -r id status event matcher entrypoint rule_path note; do
    [[ "$status" == "active" ]] || continue

    if [[ ! -f "$SKILL_ROOT/$rule_path" ]]; then
      printf 'missing active rule_path: %s -> %s\n' "$id" "$rule_path" >&2
      missing=1
    fi

    if [[ ! -f "$SKILL_ROOT/$entrypoint" ]]; then
      printf 'missing active entrypoint: %s -> %s\n' "$id" "$entrypoint" >&2
      missing=1
    fi
  done < <(list_registry_bindings)

  return "$missing"
}

clean_managed_hooks() {
  local target_file="$1"

  if [[ ! -f "$target_file" ]]; then
    jq -n '{hooks:{}}'
    return
  fi

  jq \
    --arg prefix "$MANAGED_PREFIX" \
    --arg command_root "$COMMAND_ROOT" \
    '
      .hooks = (.hooks // {}) |
      .hooks |= with_entries(
        .value |= [
          .[]? |
          .hooks = [
            .hooks[]? |
            select(
              (
                ((.statusMessage // "") | startswith($prefix)) or
                ((.command // "") | startswith($command_root))
              ) | not
            )
          ] |
          select((.hooks | length) > 0)
        ]
      ) |
      .hooks |= with_entries(select(.value | length > 0))
    ' "$target_file"
}

build_desired_groups() {
  local desired='{}'
  local id status event matcher entrypoint rule_path note
  local group_json

  while IFS=$'\t' read -r id status event matcher entrypoint rule_path note; do
    [[ "$status" == "active" ]] || continue

    group_json=$(jq -n \
      --arg id "$id" \
      --arg matcher "$matcher" \
      --arg command "$SKILL_ROOT/$entrypoint" \
      '{
        matcher: $matcher,
        hooks: [
          {
            type: "command",
            command: $command,
            statusMessage: ("better-test: " + $id)
          }
        ]
      }')

    desired=$(jq \
      --arg event "$event" \
      --arg matcher "$matcher" \
      --argjson group "$group_json" \
      '
        .[$event] = (.[$event] // []) |
        if any(.[$event][]?; .matcher == $matcher) then
          .[$event] = [
            .[$event][] |
            if .matcher == $matcher then
              .hooks += $group.hooks
            else
              .
            end
          ]
        else
          .[$event] += [$group]
        end
      ' <<< "$desired")
  done < <(list_registry_bindings)

  printf '%s\n' "$desired"
}

merge_hooks() {
  local base_json="$1"
  local desired_json="$2"
  local result_json="$base_json"
  local event
  local group
  local matcher

  while IFS= read -r event; do
    while IFS= read -r group; do
      matcher=$(jq -r '.matcher' <<< "$group")
      result_json=$(jq \
        --arg event "$event" \
        --arg matcher "$matcher" \
        --argjson group "$group" \
        '
          .hooks = (.hooks // {}) |
          .hooks[$event] = (.hooks[$event] // []) |
          if any(.hooks[$event][]?; .matcher == $matcher) then
            .hooks[$event] = [
              .hooks[$event][] |
              if .matcher == $matcher then
                .hooks += $group.hooks
              else
                .
              end
            ]
          else
            .hooks[$event] += [$group]
          end
        ' <<< "$result_json")
    done < <(jq -c --arg event "$event" '.[$event][]?' <<< "$desired_json")
  done < <(jq -r 'keys[]' <<< "$desired_json")

  printf '%s\n' "$result_json"
}

install_hooks() {
  local target_dir="$PROJECT_ROOT/.codex"
  local target_file="$target_dir/hooks.json"
  local test_root=""
  local cleaned_json
  local desired_json
  local merged_json

  test_root=$(bt_resolve_test_dir "$PROJECT_ROOT") || {
    echo "better-test test root could not be resolved for $PROJECT_ROOT" >&2
    echo "add a repository .better-test-root file (for example: test) or initialize .better-work/test" >&2
    exit 1
  }

  if ! has_feature_flag; then
    if [[ "$ENABLE_FEATURE_FLAG" == "true" ]]; then
      enable_feature_flag
    else
      echo "$HOOK_FEATURE_KEY feature is disabled in $CONFIG_FILE and not enabled by the current Codex runtime" >&2
      echo "re-run with --enable-feature-flag to update the user config explicitly" >&2
      exit 1
    fi
  fi

  validate_active_entries
  mkdir -p "$target_dir"

  cleaned_json=$(clean_managed_hooks "$target_file")
  desired_json=$(build_desired_groups)
  merged_json=$(merge_hooks "$cleaned_json" "$desired_json")
  printf '%s\n' "$merged_json" > "$target_file"

  echo "test root: $test_root"
  echo "installed better-test Codex hooks into $target_file"
}

uninstall_hooks() {
  local target_file="$PROJECT_ROOT/.codex/hooks.json"
  local cleaned_json

  if [[ ! -f "$target_file" ]]; then
    echo "no hooks file at $target_file"
    return
  fi

  cleaned_json=$(clean_managed_hooks "$target_file")
  printf '%s\n' "$cleaned_json" > "$target_file"
  echo "removed better-test Codex hooks from $target_file"
}

status_hooks() {
  local target_file="$PROJECT_ROOT/.codex/hooks.json"
  local test_root=""
  local id status
  local installed=false

  echo "project: $PROJECT_ROOT"
  echo "hooks file: $target_file"

  test_root=$(bt_resolve_test_dir "$PROJECT_ROOT") || test_root="unresolved"
  echo "test root: $test_root"

  if has_feature_flag; then
    echo "feature flag: enabled ($HOOK_FEATURE_KEY)"
  else
    echo "feature flag: disabled ($HOOK_FEATURE_KEY)"
  fi

  if [[ -f "$target_file" ]]; then
    echo "hooks.json: present"
  else
    echo "hooks.json: missing"
  fi

  while IFS=$'\t' read -r id status; do
    if [[ -f "$target_file" ]] && jq -e --arg msg "better-test: $id" '
      any(.hooks[]?[]?.hooks[]?; (.statusMessage // "") == $msg)
    ' "$target_file" >/dev/null 2>&1; then
      installed=true
      printf '%s\t%s\tinstalled\n' "$id" "$status"
    else
      printf '%s\t%s\tnot-installed\n' "$id" "$status"
    fi
  done < <(jq -r '.hooks[] | [.id, .platforms.codex.status] | @tsv' "$REGISTRY_FILE")

  if [[ "$installed" == "false" ]]; then
    echo "no better-test Codex hook entries installed"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ROOT=$(resolve_project_root "$2")
      shift 2
      ;;
    --enable-feature-flag)
      ENABLE_FEATURE_FLAG=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$(resolve_project_root)}"

case "$COMMAND" in
  install)
    install_hooks
    ;;
  uninstall)
    uninstall_hooks
    ;;
  status)
    status_hooks
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
