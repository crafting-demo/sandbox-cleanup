#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Minimal configurable criteria
# -----------------------------------------------------------------------------
# Comma-separated list of template names to include. Leave empty to include all.
TEMPLATES_CSV=""

# Only include sandboxes whose names start with this prefix. Empty = no name filter.
SANDBOX_NAME_PREFIX=""

# Include sandboxes whose last activity is older than this many days.
# Uses meta.accessed_at when available; otherwise falls back to meta.updated_at.
# Empty = no inactivity filter.
LAST_ACTIVE_BEFORE_DAYS=""

# Runtime flags
# Set via CLI flags; defaults maintain read-only behavior
FORCE_DELETE=false

# -----------------------------------------------------------------------------
# CLI args parsing
# -----------------------------------------------------------------------------
while [[ ${#} -gt 0 ]]; do
  case "${1}" in
    --force-delete|-F|-f)
      FORCE_DELETE=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown argument: ${1}" >&2
      exit 2
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
days_ago_to_epoch_cutoff() {
  local days="$1"
  date -u -d "-$days days" +%s
}

# Normalize sandbox name by stripping all prefixes (keep last segment after '/')
normalize_sandbox_name() {
  local name="$1"
  echo "${name##*/}"
}

# Delete sandbox non-interactively using the canonical command
delete_sandbox_non_interactive() {
  local raw_name="$1"
  local name
  name=$(normalize_sandbox_name "${raw_name}")

  if ! command -v cs >/dev/null 2>&1; then
    echo "cs CLI not found in PATH" >&2
    return 127
  fi

  if cs sandbox remove "${name}" --force --wait >/dev/null 2>&1; then
    echo "Deleted sandbox: ${name}" >&2
    return 0
  fi

  echo "Failed to delete sandbox: ${name}" >&2
  return 1
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


# Optional destructive step: force delete matched sandboxes
if [[ "${FORCE_DELETE}" == "true" ]]; then
  # Extract names from filtered stream
  names=$(echo "${filtered}" | jq -r '(.meta.name // empty)')

  if [[ -z "${names}" ]]; then
    echo "No sandboxes matched the filter; nothing to delete." >&2
  else
    echo "Force deletion requested; attempting to delete matched sandboxes..." >&2
    while IFS= read -r sb_name; do
      [[ -z "${sb_name}" ]] && continue
      delete_sandbox_non_interactive "${sb_name}" || true
    done <<< "${names}"
  fi
fi


