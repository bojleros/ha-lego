# LEGO INWX Certificates Home Assistant Add-on

This Home Assistant add-on provisions and renews Let's Encrypt certificates using [lego](https://go-acme.github.io/lego/) with the INWX DNS challenge. Certificates are stored persistently in the add-on data directory and copied into Home Assistant's `/ssl` volume for use by other services.

## Features

- Uses lego's ACME client with the INWX DNS provider
- Supports multiple domains and wildcard certificates
- Runs automated renewals on a configurable cron schedule
- Copies certificate, key, issuer, and full chain files into `/ssl`
- Supports INWX two-factor authentication (shared secret or TOTP pin)
- Optional staging mode for testing against Let's Encrypt's staging endpoint

## Configuration

Set the options from the Home Assistant add-on UI. All INWX credentials are stored securely by Home Assistant.

| Option | Description |
| --- | --- |
| `email` | Email address used for the ACME account. Required. |
| `domains` | List of domains (or wildcard domains) to include on the certificate. Required. |
| `key_type` | Key algorithm (`rsa2048`, `rsa4096`, `ec256`, or `ec384`). Defaults to `rsa2048`. |
| `cron_schedule` | Cron expression controlling renewal frequency. Defaults to `0 3 * * *` (daily at 03:00). |
| `renew_days` | Renew when certificates expire within this many days. Defaults to `30`. |
| `lego_path` | Internal directory for lego state. Defaults to `/data/lego`. |
| `staging` | When `true`, use Let's Encrypt's staging environment. Useful for testing. |
| `inwx_username` | INWX account username (usually the account number). Required. |
| `inwx_password` | INWX account password. Required. |
| `inwx_shared_secret` | Optional INWX shared secret for TOTP-based 2FA. |
| `inwx_totp` | Optional static TOTP pin for INWX. |

Certificates are copied into `/ssl` with filenames based on the domain (wildcards are converted to `_`). For example, `example.com` produces:

- `/ssl/example.com.crt`
- `/ssl/example.com.key`
- `/ssl/example.com.issuer.crt`
- `/ssl/example.com.fullchain.pem`

A wildcard such as `*.example.com` is stored as `/ssl/_.example.com.*`.

## Operation

On startup the add-on validates the configuration, runs an initial issuance or renewal, and then starts `crond` to execute future renewals on the specified schedule. Renewal logs are written to the add-on log.

If the initial certificate issuance fails (for example due to incorrect credentials or DNS propagation issues), the add-on will stop so the error can be corrected. Update the configuration and start the add-on again once the issue is resolved.
