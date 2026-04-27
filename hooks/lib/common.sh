#!/bin/bash

bt_resolve_link_target() {
  local link_path="$1"
  local target

  target=$(readlink "$link_path" 2>/dev/null) || return 1

  if [[ "$target" = /* ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  (
    cd "$(dirname "$link_path")" 2>/dev/null || exit 1
    cd "$target" 2>/dev/null || exit 1
    pwd
  )
}

bt_resolve_test_dir() {
  local cwd="$1"
  local project_name
  local shared_root

  if [[ -z "$cwd" ]]; then
    return 1
  fi

  if [[ -d "$cwd/.better-work/test" ]]; then
    printf '%s\n' "$cwd/.better-work/test"
    return 0
  fi

  if [[ -L "$cwd/.better-work" ]]; then
    shared_root=$(bt_resolve_link_target "$cwd/.better-work") || shared_root=""
    if [[ -n "$shared_root" && -d "$shared_root/test" ]]; then
      printf '%s\n' "$shared_root/test"
      return 0
    fi
  fi

  project_name=$(basename "$cwd")
  if [[ -d "$HOME/.better-work/$project_name/test" ]]; then
    printf '%s\n' "$HOME/.better-work/$project_name/test"
    return 0
  fi

  return 1
}

bt_find_session_run_dir() {
  local test_dir="$1"
  local session_file=""
  local run_dir_rel=""

  session_file=$(bt_find_session_file "$test_dir") || return 1
  run_dir_rel=$(jq -r '.run_dir // empty' < "$session_file" 2>/dev/null)
  if [[ -n "$run_dir_rel" ]]; then
    printf '%s\n' "$test_dir/$run_dir_rel"
    return 0
  fi

  return 1
}

bt_find_session_file() {
  local test_dir="$1"
  local session_dir="$test_dir/.active-sessions"
  local parent_pid=""
  local grandparent_pid=""
  local pid

  if [[ ! -d "$session_dir" ]]; then
    return 1
  fi

  if [[ -n "${PPID:-}" ]]; then
    parent_pid="$PPID"
    grandparent_pid=$(ps -o ppid= -p "$parent_pid" 2>/dev/null | tr -d ' ')
  fi

  for pid in "$parent_pid" "$grandparent_pid"; do
    if [[ -z "$pid" || ! -f "$session_dir/$pid.json" ]]; then
      continue
    fi

    printf '%s\n' "$session_dir/$pid.json"
    return 0
  done

  return 1
}

bt_resolve_execution_log_file() {
  local test_dir="$1"
  local run_dir=""

  run_dir=$(bt_find_session_run_dir "$test_dir") || run_dir=""
  if [[ -n "$run_dir" && -d "$run_dir" ]]; then
    printf '%s\n' "$run_dir/execution-log.md"
    return 0
  fi

  printf '%s\n' "$test_dir/execution-log.md"
}

bt_extract_bash_write_targets() {
  local command="$1"
  local cwd="$2"

  # Best-effort extraction for Codex Bash hooks.
  # This is intentionally not a full shell parser: it covers common direct write
  # shapes used by our guards, but known bypasses remain, including:
  # - dd of=path
  # - ln -sf target name
  # - inline interpreters such as python/node/perl opening files themselves
  # - process substitution like >(file)
  # - awk -i inplace
  # - paths assembled via shell variables
  BT_COMMAND_INPUT="$command" BT_COMMAND_CWD="$cwd" python3 - <<'PY'
import os
import shlex

command = os.environ.get("BT_COMMAND_INPUT", "")
cwd = os.environ.get("BT_COMMAND_CWD", "")
lexer = shlex.shlex(command, posix=True, punctuation_chars="|&;()<>")
lexer.whitespace_split = True
tokens = list(lexer)

separators = {";", "&&", "||", "|", "&", "(", ")"}
redirect_ops = {">", ">>", ">|"}
results = []

def pathlike(token):
    if not token or token in {"-", ""}:
        return False
    if any(ch in token for ch in ("$", "*", "?", "`")):
        return False
    return True

def resolve(token):
    if not pathlike(token):
        return None
    if os.path.isabs(token):
        return os.path.normpath(token)
    if not cwd:
        return None
    return os.path.normpath(os.path.abspath(os.path.join(cwd, token)))

def add(token):
    resolved = resolve(token)
    if resolved and resolved not in results:
        results.append(resolved)

def segment_end(start):
    end = start
    while end < len(tokens) and tokens[end] not in separators:
        end += 1
    return end

i = 0
while i < len(tokens):
    tok = tokens[i]

    if tok in redirect_ops and i + 1 < len(tokens):
        add(tokens[i + 1])
        i += 2
        continue

    if tok.isdigit() and i + 2 < len(tokens) and tokens[i + 1] in redirect_ops:
        add(tokens[i + 2])
        i += 3
        continue

    if tok == "tee":
        end = segment_end(i + 1)
        j = i + 1
        while j < end:
            candidate = tokens[j]
            if candidate == "--":
                j += 1
                continue
            if candidate.startswith("-"):
                j += 1
                continue
            if candidate in redirect_ops:
                break
            add(candidate)
            j += 1
        i = end
        continue

    if tok in {"mv", "cp", "install"}:
        end = segment_end(i + 1)
        operands = [t for t in tokens[i + 1:end] if t and not t.startswith("-") and t not in redirect_ops]
        if operands:
            add(operands[-1])
        i = end
        continue

    if tok == "sed":
        end = segment_end(i + 1)
        segment = tokens[i + 1:end]
        if any(item == "-i" or item.startswith("-i") for item in segment):
            operands = [t for t in segment if t and not t.startswith("-") and t not in redirect_ops]
            if operands:
                add(operands[-1])
        i = end
        continue

    if tok in {"perl", "ruby"}:
        end = segment_end(i + 1)
        segment = tokens[i + 1:end]
        if any(item == "-i" or item.startswith("-i") for item in segment):
            operands = [t for t in segment if t and not t.startswith("-") and t not in redirect_ops]
            if operands:
                add(operands[-1])
        i = end
        continue

    if tok in {"touch", "truncate"}:
        end = segment_end(i + 1)
        for candidate in tokens[i + 1:end]:
            if candidate.startswith("-") or candidate in redirect_ops:
                continue
            add(candidate)
        i = end
        continue

    i += 1

for item in results:
    print(item)
PY
}

_bt_parse_apply_patch() {
  local mode="$1"
  local command="$2"
  local cwd="$3"
  local target="${4:-}"

  BT_APPLY_PATCH_MODE="$mode" \
  BT_APPLY_PATCH_COMMAND="$command" \
  BT_APPLY_PATCH_CWD="$cwd" \
  BT_APPLY_PATCH_TARGET="$target" \
  python3 - <<'PY'
import os
import sys

mode = os.environ.get("BT_APPLY_PATCH_MODE", "")
command = os.environ.get("BT_APPLY_PATCH_COMMAND", "")
cwd = os.environ.get("BT_APPLY_PATCH_CWD", "")
target = os.environ.get("BT_APPLY_PATCH_TARGET", "")


def resolve(path):
    if not path:
        return None
    if os.path.isabs(path):
        return os.path.normpath(path)
    if not cwd:
        return None
    return os.path.normpath(os.path.abspath(os.path.join(cwd, path)))


changes = []
current = None

for raw_line in command.splitlines():
    if raw_line.startswith("*** Add File: "):
        path = resolve(raw_line[len("*** Add File: "):].strip())
        current = {"paths": [], "added": []}
        if path:
            current["paths"].append(path)
        changes.append(current)
        continue

    if raw_line.startswith("*** Update File: "):
        path = resolve(raw_line[len("*** Update File: "):].strip())
        current = {"paths": [], "added": []}
        if path:
            current["paths"].append(path)
        changes.append(current)
        continue

    if raw_line.startswith("*** Delete File: "):
        path = resolve(raw_line[len("*** Delete File: "):].strip())
        current = {"paths": [], "added": []}
        if path:
            current["paths"].append(path)
        changes.append(current)
        continue

    if raw_line.startswith("*** Move to: ") and current is not None:
        path = resolve(raw_line[len("*** Move to: "):].strip())
        if path and path not in current["paths"]:
            current["paths"].append(path)
        continue

    if raw_line.startswith("+") and not raw_line.startswith("+++"):
        if current is not None:
            current["added"].append(raw_line[1:])


if mode == "targets":
    seen = set()
    for change in changes:
        for path in change["paths"]:
            if path and path not in seen:
                seen.add(path)
                print(path)
    sys.exit(0)

if mode == "added":
    for change in changes:
        if target and target in change["paths"]:
            for line in change["added"]:
                print(line)
    sys.exit(0)

sys.exit(1)
PY
}

bt_extract_apply_patch_targets() {
  local command="$1"
  local cwd="$2"
  _bt_parse_apply_patch "targets" "$command" "$cwd"
}

bt_extract_apply_patch_added_content() {
  local command="$1"
  local cwd="$2"
  local target="$3"
  _bt_parse_apply_patch "added" "$command" "$cwd" "$target"
}

bt_extract_codex_write_targets() {
  local tool_name="$1"
  local command="$2"
  local cwd="$3"

  case "$tool_name" in
    Bash)
      bt_extract_bash_write_targets "$command" "$cwd"
      ;;
    apply_patch)
      bt_extract_apply_patch_targets "$command" "$cwd"
      ;;
  esac
}

bt_extract_codex_write_added_content() {
  local tool_name="$1"
  local command="$2"
  local cwd="$3"
  local target="$4"

  case "$tool_name" in
    Bash)
      printf '%s\n' "$command"
      ;;
    apply_patch)
      bt_extract_apply_patch_added_content "$command" "$cwd" "$target"
      ;;
  esac
}
