#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Minimal configurable criteria
# -----------------------------------------------------------------------------
# Comma-separated list of template names to include. Leave empty to include all.
TEMPLATES_CSV=""

# Only include sandboxes whose names start with this prefix. Empty = no name filter.
SANDBOX_NAME_PREFIX="sb"

# Include sandboxes whose last activity is older than this many days.
# Uses meta.accessed_at when available; otherwise falls back to meta.updated_at.
# Empty = no inactivity filter.
LAST_ACTIVE_BEFORE_DAYS=""

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
days_ago_to_epoch_cutoff() {
  local days="$1"
  date -u -d "-$days days" +%s
}

# -----------------------------------------------------------------------------
# Build base command
# -----------------------------------------------------------------------------
cmd=(cs sb list)
if [[ -n "${TEMPLATES_CSV}" ]]; then
  cmd+=( -t "${TEMPLATES_CSV}" )
fi
cmd+=( -o json )

# -----------------------------------------------------------------------------
# Execute list and filter via jq
# -----------------------------------------------------------------------------
json_output=$("${cmd[@]}")

# Precompute inactivity cutoff
last_active_before_epoch=""
if [[ -n "${LAST_ACTIVE_BEFORE_DAYS}" ]]; then
  last_active_before_epoch=$(days_ago_to_epoch_cutoff "${LAST_ACTIVE_BEFORE_DAYS}")
fi

# Build jq args and static filter program to avoid shell-quoting pitfalls
jq_args=( -r --arg name_prefix "${SANDBOX_NAME_PREFIX}" )
if [[ -n "${last_active_before_epoch}" ]]; then
  jq_args+=( --argjson last_active_before "${last_active_before_epoch}" )
else
  jq_args+=( --argjson last_active_before null )
fi

jq_program='.
  []
  | select(
      (($name_prefix == "") or ((.meta.name // "") | startswith($name_prefix)))
      and
      (($last_active_before == null) or (((.meta.accessed_at // .meta.updated_at) | gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) <= $last_active_before))
    )'

filtered=$(echo "${json_output}" | jq "${jq_args[@]}" "${jq_program}")

# Table output: print key columns in a readable table
printf "NAME\tSTATE\tTEMPLATE\tOWNER\tCREATED_AT\tLAST_ACTIVE\n"
echo "${filtered}" | jq -r '
  [
    (.meta.name // ""),
    (.status.sandbox.lifecycle_stage // .spec.op_state.state // ""),
    (.meta.version // ""),
    (.meta.owner.name // ""),
    (.meta.created_at // ""),
    ((.meta.accessed_at // .meta.updated_at) // "")
  ] | @tsv
'


