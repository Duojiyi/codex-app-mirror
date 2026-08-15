# Download statistics workflow

The `Update Download Stats` workflow maintains the cumulative download count in
Cloudflare R2. Its credentials are intentionally scoped to the GitHub
`download-stats` environment instead of being shared with every repository job.

## Enablement

Scheduled runs are opt-in so that mirrors and development copies do not fail
or write to production infrastructure they do not own. Create the repository
variable `DOWNLOAD_STATS_ENABLED` with the value `true` only after the R2
bucket, environment variable, and environment secrets below are configured.
An unset value or `false` skips scheduled runs. Manual runs are always allowed
and execute the configuration preflight.

## Required environment configuration

Configure the `download-stats` environment in **Settings → Environments**.
Restrict deployment branches to `main`, and do not add required reviewers: the
daily scheduled job cannot approve an environment deployment.

Add this environment variable:

| Variable | Value |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | The Cloudflare account ID that owns the R2 bucket. |

For backward compatibility the workflow also accepts a secret with this name,
but a GitHub variable is preferred because an account ID is not a credential.

Add these environment secrets:

| Secret | Minimum scope |
| --- | --- |
| `CF_ANALYTICS_API_TOKEN` | Cloudflare API token limited to the target account with **Account Analytics: Read**. |
| `R2_ACCESS_KEY_ID` | Access key from an R2 API token limited to the `codex-app-mirror` bucket. |
| `R2_SECRET_ACCESS_KEY` | Secret key for the same R2 token. |

The R2 token needs **Object Read & Write** because the workflow reads and writes
`stats/state.json` and writes `stats/downloads.json`. Do not use a Global API
Key or an account-wide R2 token.

## Rotation and verification

1. Rotate both tokens periodically and immediately after suspected exposure.
2. Update the environment secrets before revoking the old tokens.
3. Run **Actions → Update Download Stats → Run workflow**.
4. Confirm that `Update cumulative download badge` succeeds and that
   `stats/downloads.json` has a recent `updatedAt` value in R2.

The workflow validates every required setting before checking out third-party
code, pins `actions/checkout` to an immutable commit, disables persisted Git
credentials, uses the runner-provided AWS CLI, and has a ten-minute timeout.
