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
      echo "better-test L1 Hook: Credential detected in $context. Matched pattern near: ${matched:0:30}... Remove credentials before writing to the project test root." >&2
      return 2
    fi
  done

  return 0
}

bt_credential_scan_interactive_command() {
  local command="$1"
  local context="$2"
  local pattern
  local patterns=(
    'macos-credential-broker[^;&|]*[[:space:]]rotate([[:space:]]|$)'
    '\$[{]?BROKER[}]?["'"'"']?[[:space:]]+rotate([[:space:]]|$)'
    '(^|[;&|[:space:]])([^;&|[:space:]]*/)?futucli[^;&|]*(set-login-pwd|set-trade-pwd)([[:space:]]|$)'
    'dedicated-test-account\.py[^;&|]*[[:space:]]enroll([[:space:]]|$)'
    '(^|[/[:space:]])(password-bootstrap|broker-rotate)\.command([[:space:]]|$)'
  )

  if [[ -z "$command" ]]; then
    return 0
  fi

  for pattern in "${patterns[@]}"; do
    if printf '%s\n' "$command" | grep -qE "$pattern"; then
      echo "better-test L1 Hook: Interactive credential setup is forbidden in $context. Active test work must use profile_id-only status/materialize/unlock flows; missing or rejected credentials become BLOCKED_CREDENTIAL_PROFILE instead of a password prompt." >&2
      return 2
    fi
  done

  return 0
}
