### sb_cleanup.sh – Parameters and Usage

**Purpose**: Template repo demonstrating a scheduled cron job sandbox that finds and removes sandboxes matching configurable criteria.

### Selection criteria

- Templates: include only sandboxes created from specific templates (`TEMPLATES_CSV`).
- Name prefixes: include only sandboxes whose names start with given prefixes (`SANDBOX_NAME_PREFIX`).
- Inactivity: include only sandboxes inactive for at least N days (`LAST_ACTIVE_BEFORE_DAYS`).

### Parameters

- **TEMPLATES_CSV**: Comma-separated template names to include. Empty = include all.
  - Example: `"backend,frontend-ci"`

- **SANDBOX_NAME_PREFIX**: Only include sandboxes whose names start with this prefix. Empty = no filter.
  - Example: `"lab-"`

- **LAST_ACTIVE_BEFORE_DAYS**: Include sandboxes whose last activity is older than N days.
  - Last activity uses `meta.accessed_at` when available, else `meta.updated_at`.
  - Example: `"14"` (sandboxes inactive for at least 14 days)

### Flags

- `--force-delete` (or `-F`/`-f`): Force delete all matched sandboxes using `cs sandbox remove NAME --force --wait`.

Notes:
- Sandbox names are normalized before deletion by stripping all prefixes and keeping only the last path segment after `/` (e.g., `folder/subfolder/my-sb` → `my-sb`).
- The script never prompts when `--force-delete` is used; deletions are non-interactive.

### How it works

- Builds `cs sb list` with optional template filter and outputs JSON
- Computes an inactivity cutoff epoch if `LAST_ACTIVE_BEFORE_DAYS` is set
- Filters with `jq` for name prefix and inactivity window
- Prints a TSV table: NAME, STATE, TEMPLATE, OWNER, CREATED_AT, LAST_ACTIVE
- If `--force-delete` is provided, deletes each matched sandbox via `cs sandbox remove NAME --force --wait`

### Examples

Filter by template and prefix:

```bash
TEMPLATES_CSV="backend,frontend-ci" SANDBOX_NAME_PREFIX="sb-" ./sb_cleanup.sh
```

Only show sandboxes inactive for 30+ days:

```bash
LAST_ACTIVE_BEFORE_DAYS="30" ./sb_cleanup.sh
```

Combine all filters:

```bash
TEMPLATES_CSV="backend" SANDBOX_NAME_PREFIX="sb" LAST_ACTIVE_BEFORE_DAYS="7" ./sb_cleanup.sh
```

Delete matched sandboxes (non-interactive):

```bash
./sb_cleanup.sh --force-delete
```

### Scheduling (via sandbox.yaml)

`sandbox.yaml` can define a job named `housekeep` that runs `./sb_cleanup.sh` on a schedule:

```yaml
jobs:
  housekeep:
    run:
      cmd: ./sb_cleanup.sh --force-delete
    schedule: "0 23 * * *"
    disable_on_start: true
```

Set `disable_on_start` as needed to enable/disable the scheduled run.


