#!/usr/bin/env bash

render_template() {
  local template_file="$1" output_file="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  cp "$template_file" "$tmp"
  while [[ $# -gt 0 ]]; do
    local key="$1" value="$2"
    shift 2
    value=${value//\/\\}
    value=${value//&/\&}
    value=${value//"/\"}
    sed -i "s/{{$key}}/$value/g" "$tmp"
  done
  ensure_file_contents "$output_file" "$(cat "$tmp")" 640 root root
  rm -f "$tmp"
}

