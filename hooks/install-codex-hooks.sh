#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_FILE="$SCRIPT_DIR/registry.json"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"
MANAGED_PREFIX="better-test:"
COMMAND_ROOT="$SKILL_ROOT/hooks/codex/"

COMMAND="${1:-install}"
shift || true

PROJECT_ROOT=""
ENABLE_FEATURE_FLAG=false

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
  [[ -f "$CONFIG_FILE" ]] || return 1

  awk '
    /^\[features\][[:space:]]*$/ { in_features=1; next }
    /^\[/ { in_features=0 }
    in_features && /^[[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*true([[:space:]]|$)/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$CONFIG_FILE"
}

enable_feature_flag() {
  local backup_file
  local temp_file

  mkdir -p "$CODEX_HOME"
  backup_file="$CONFIG_FILE.backup-$(date +%Y%m%d%H%M%S)"
  temp_file="$(mktemp)"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$temp_file" <<'EOF'
[features]
codex_hooks = true
EOF
    mv "$temp_file" "$CONFIG_FILE"
    echo "enabled codex_hooks in $CONFIG_FILE"
    return
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$backup_file"
  fi

  awk '
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
        print "codex_hooks = true"
        inserted = 1
      }
      in_features = 0
      print
      next
    }
    {
      if (in_features && /^[[:space:]]*codex_hooks[[:space:]]*=/) {
        print "codex_hooks = true"
        inserted = 1
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
        print "codex_hooks = true"
      } else if (in_features && !inserted) {
        print "codex_hooks = true"
      }
    }
  ' "$CONFIG_FILE" 2>/dev/null > "$temp_file"

  mv "$temp_file" "$CONFIG_FILE"
  printf 'enabled codex_hooks in %s' "$CONFIG_FILE"
  if [[ -f "$backup_file" ]]; then
    printf ' (backup: %s)' "$backup_file"
  fi
  printf '\n'
}

list_registry_rows() {
  jq -r '
    .hooks[]
    | [
        .id,
        .platforms.codex.status,
        .platforms.codex.event,
        .platforms.codex.matcher,
        .platforms.codex.entrypoint,
        .rule_path,
        (.platforms.codex.note // "")
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
  done < <(list_registry_rows)

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
  done < <(list_registry_rows)

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
  local cleaned_json
  local desired_json
  local merged_json

  if ! has_feature_flag; then
    if [[ "$ENABLE_FEATURE_FLAG" == "true" ]]; then
      enable_feature_flag
    else
      echo "codex_hooks feature flag is disabled in $CONFIG_FILE" >&2
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
  local id status event matcher entrypoint rule_path note
  local installed=false

  echo "project: $PROJECT_ROOT"
  echo "hooks file: $target_file"

  if has_feature_flag; then
    echo "feature flag: enabled"
  else
    echo "feature flag: disabled"
  fi

  if [[ -f "$target_file" ]]; then
    echo "hooks.json: present"
  else
    echo "hooks.json: missing"
  fi

  while IFS=$'\t' read -r id status event matcher entrypoint rule_path note; do
    if [[ -f "$target_file" ]] && jq -e --arg msg "better-test: $id" '
      any(.hooks[]?[]?.hooks[]?; (.statusMessage // "") == $msg)
    ' "$target_file" >/dev/null 2>&1; then
      installed=true
      printf '%s\t%s\tinstalled\n' "$id" "$status"
    else
      printf '%s\t%s\tnot-installed\n' "$id" "$status"
    fi
  done < <(list_registry_rows)

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
