#!/bin/bash

bt_credential_scan_content() {
  local content="$1"
  local context="$2"
  local matched=""
  local pattern
  local patterns=(
    'password[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{4,}'
    'token[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
    'api_key[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
    'api[-_]?secret[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
    'secret_key[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
    'access_key[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
    'Bearer[[:space:]]+[A-Za-z0-9_\-\.]{20,}'
  )

  if [[ -z "$content" ]]; then
    return 0
  fi

  for pattern in "${patterns[@]}"; do
    if printf '%s\n' "$content" | grep -qiE "$pattern"; then
      matched=$(printf '%s\n' "$content" | grep -oiE "$pattern" | head -1)
      echo "better-test L1 Hook: Credential detected in $context. Matched pattern near: ${matched:0:30}... Remove credentials before writing to .better-work/ files." >&2
      return 2
    fi
  done

  return 0
}
