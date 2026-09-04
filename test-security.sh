#!/usr/bin/env bash
set -euo pipefail

source_file="$(dirname "$0")/Widget.qml"

forbidden=(
  'updateCheckProc'
  'updateProc'
  'plugin update'
  'https://raw.githubusercontent.com/'
)

for token in "${forbidden[@]}"; do
  if rg -Fq "$token" "$source_file"; then
    printf 'forbidden updater token remains: %s\n' "$token" >&2
    exit 1
  fi
done

rg -Fq 'property int maxConfigBytes: 65536' "$source_file"
rg -Fq 'property int maxAccounts: 64' "$source_file"
rg -Fq 'property int maxFieldLength: 256' "$source_file"
rg -Fq 'function utf8ByteLength(value)' "$source_file"
rg -Fq 'utf8ByteLength(rawText) > root.maxConfigBytes' "$source_file"
rg -Fq 'data.accounts.length > root.maxAccounts' "$source_file"
rg -Fq 'a[field].length > root.maxFieldLength' "$source_file"
rg -Fq 'command: ["head", "-c", String(root.maxConfigBytes + 1), "--", root.accountsPath]' "$source_file"

printf 'security regression checks passed\n'
