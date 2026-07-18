#!/bin/sh

SKILL_NAME="better-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

command="${1:-install}"
linked_platforms=""
removed_platforms=""
reminders=""
had_error=0
source_commit="unversioned"
source_state="not-a-git-checkout"

say() {
  printf '%s %s\n' "$1" "$2"
}

append_csv() {
  var_name=$1
  value=$2
  eval "current_value=\${$var_name}"
  if [ -n "$current_value" ]; then
    eval "$var_name=\$current_value,\\ \$value"
  else
    eval "$var_name=\$value"
  fi
}

resolve_dir() {
  if [ ! -d "$1" ]; then
    return 1
  fi
  (
    cd "$1" 2>/dev/null || exit 1
    pwd -P
  )
}

SCRIPT_REAL="$(resolve_dir "$SCRIPT_DIR")"

if git -C "$SCRIPT_REAL" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_commit="$(git -C "$SCRIPT_REAL" rev-parse HEAD 2>/dev/null || printf '%s' unknown)"
  if [ -n "$(git -C "$SCRIPT_REAL" status --porcelain 2>/dev/null)" ]; then
    source_state="dirty"
  else
    source_state="clean"
  fi
fi

print_source_provenance() {
  say "→" "canonical source: $SCRIPT_REAL"
  say "→" "source revision: $source_commit ($source_state)"
}

link_matches_script_dir() {
  target=$1
  if [ ! -L "$target" ]; then
    return 1
  fi

  target_real="$(resolve_dir "$target")" || return 1
  [ "$target_real" = "$SCRIPT_REAL" ]
}

link_target_text() {
  readlink "$1" 2>/dev/null || printf '%s' 'unknown target'
}

install_link() {
  label=$1
  base_dir=$2
  target="$base_dir/$SKILL_NAME"

  if [ -L "$target" ]; then
    if link_matches_script_dir "$target"; then
      say "→" "$label: already linked"
      append_csv linked_platforms "$label"
    else
      say "⚠" "$label: target points elsewhere ($(link_target_text "$target")); skipping"
    fi
    return
  fi

  if [ -e "$target" ]; then
    if [ -d "$target" ]; then
      say "⚠" "$label: unmanaged directory at $target; move or back it up, then rerun so updates come from the canonical source"
    else
      say "⚠" "$label: target exists and is not a symlink; skipping"
    fi
    return
  fi

  if ! mkdir -p "$base_dir"; then
    say "✗" "$label: failed to create parent directory $base_dir"
    had_error=1
    return
  fi

  if ln -s "$SCRIPT_REAL" "$target"; then
    say "✓" "$label: linked $target"
    append_csv linked_platforms "$label"
  else
    say "✗" "$label: failed to create symlink at $target"
    had_error=1
  fi
}

uninstall_link() {
  label=$1
  base_dir=$2
  target="$base_dir/$SKILL_NAME"

  if [ -L "$target" ]; then
    if link_matches_script_dir "$target"; then
      if rm "$target"; then
        say "✓" "$label: removed $target"
        append_csv removed_platforms "$label"
      else
        say "✗" "$label: failed to remove $target"
        had_error=1
      fi
    else
      say "⚠" "$label: target points elsewhere ($(link_target_text "$target")); skipping"
    fi
    return
  fi

  if [ -e "$target" ]; then
    say "⚠" "$label: target exists but is not a managed symlink; skipping"
  else
    say "→" "$label: nothing to remove"
  fi
}

status_link() {
  label=$1
  base_dir=$2
  target="$base_dir/$SKILL_NAME"

  if [ -L "$target" ]; then
    if link_matches_script_dir "$target"; then
      say "✓" "$label: linked"
      append_csv linked_platforms "$label"
    else
      say "⚠" "$label: linked elsewhere ($(link_target_text "$target"))"
    fi
    return
  fi

  if [ -e "$target" ]; then
    if [ -d "$target" ]; then
      say "⚠" "$label: unmanaged directory at $target (update provenance unavailable)"
    else
      say "⚠" "$label: non-symlink file present at $target"
    fi
  else
    say "→" "$label: not installed"
  fi
}

cursor_root_has_project() {
  root=$1
  if [ ! -d "$root" ]; then
    return 1
  fi

  for candidate in \
    "$root/.cursor" \
    "$root"/*/.cursor \
    "$root"/*/*/.cursor \
    "$root"/*/*/*/.cursor
  do
    if [ -d "$candidate" ]; then
      return 0
    fi
  done

  return 1
}

detect_cursor() {
  for root in \
    "$SCRIPT_DIR" \
    "$HOME/Code" \
    "$HOME/code" \
    "$HOME/Projects" \
    "$HOME/projects" \
    "$HOME/Workspace" \
    "$HOME/workspace" \
    "$HOME/work" \
    "$HOME/src" \
    "$HOME/repos" \
    "$HOME/git"
  do
    if cursor_root_has_project "$root"; then
      return 0
    fi
  done
  return 1
}

handle_claude() {
  label="claude-code"
  base_dir="$HOME/.claude/skills"

  if [ ! -d "$base_dir" ]; then
    if [ "$command" = "status" ]; then
      say "→" "$label: not detected"
    fi
    return
  fi

  case "$command" in
    install) install_link "$label" "$base_dir" ;;
    uninstall) uninstall_link "$label" "$base_dir" ;;
    status) status_link "$label" "$base_dir" ;;
  esac
}

handle_codex_legacy() {
  label="codex"
  base_dir="$HOME/.codex/skills"

  if [ ! -d "$base_dir" ]; then
    if [ "$command" = "status" ]; then
      say "→" "$label: not detected"
    fi
    return
  fi

  case "$command" in
    install) install_link "$label" "$base_dir" ;;
    uninstall) uninstall_link "$label" "$base_dir" ;;
    status) status_link "$label" "$base_dir" ;;
  esac
}

handle_codex_canonical() {
  label="codex-canonical"
  base_dir="$HOME/.agents/skills"

  case "$command" in
    install) install_link "$label" "$base_dir" ;;
    uninstall) uninstall_link "$label" "$base_dir" ;;
    status) status_link "$label" "$base_dir" ;;
  esac
}

handle_gemini() {
  label="gemini"
  if [ -d "$HOME/.gemini" ]; then
    append_csv reminders "$label"
    say "→" "$label: detected; add @.better-work/test/protocol.md to GEMINI.md manually"
  elif [ "$command" = "status" ]; then
    say "→" "$label: not detected"
  fi
}

handle_cursor() {
  label="cursor"
  if detect_cursor; then
    append_csv reminders "$label"
    say "→" "$label: detected; add project rules under .cursor/rules/ manually"
  elif [ "$command" = "status" ]; then
    say "→" "$label: not detected"
  fi
}

print_summary() {
  if [ -z "$linked_platforms" ]; then
    linked_platforms="none"
  fi
  if [ -z "$removed_platforms" ]; then
    removed_platforms="none"
  fi
  if [ -z "$reminders" ]; then
    reminders="none"
  fi

  case "$command" in
    uninstall)
      printf 'Removed from: %s. Reminders: %s.\n' "$removed_platforms" "$reminders"
      ;;
    status)
      printf 'Linked platforms: %s. Reminders: %s.\n' "$linked_platforms" "$reminders"
      ;;
    *)
      printf 'Installed for: %s. Reminders: %s.\n' "$linked_platforms" "$reminders"
      ;;
  esac
}

case "$command" in
  install|status|uninstall)
    ;;
  *)
    say "✗" "Unknown command: $command"
    printf 'Usage: %s [install|status|uninstall]\n' "$0"
    exit 1
    ;;
esac

print_source_provenance
handle_claude
handle_codex_legacy
handle_codex_canonical
handle_gemini
handle_cursor
print_summary

exit "$had_error"
