# LEGO DNS Certificates Home Assistant Add-on

[![Add to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdeg0nz%2Fha-lego)

This Home Assistant add-on provisions and renews Let's Encrypt certificates using [lego](https://go-acme.github.io/lego/) with DNS-based challenges. Certificates are stored persistently in the add-on data directory and copied into Home Assistant's `/ssl` volume for use by other services.

## Features

- Uses lego's ACME client with any supported DNS provider
- Supports multiple domains and wildcard certificates
- Runs automated renewals on a configurable cron schedule
- Copies certificate, key, issuer, and full chain files into `/ssl`
- Accepts provider-specific environment variables as documented by lego
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
| `dns_provider` | lego DNS provider identifier (see [lego docs](https://go-acme.github.io/lego/dns/index.html)). Defaults to `inwx`. |
| `dns_provider_env` | List of `KEY=VALUE` entries exported for the DNS provider (for example `CLOUDFLARE_API_TOKEN=...`). |
| `restart_addon_slug` | Optional slug of another add-on to restart after certificate updates. Leave blank to disable. |
| `force_initial_request` | When `true`, wipe existing lego state and force a fresh certificate issuance on next start. |

Certificates are copied into `/ssl` with filenames based on the domain (wildcards are converted to `_`). For example, `example.com` produces:

- `/ssl/example.com.crt`
- `/ssl/example.com.key`
- `/ssl/example.com.issuer.crt`
- `/ssl/example.com.fullchain.pem`

A wildcard such as `*.example.com` is stored as `/ssl/_.example.com.*`.

## Operation

On startup the add-on validates the configuration, runs an initial issuance or renewal, and then starts `crond` to execute future renewals on the specified schedule. Renewal logs are written to the add-on log.

If the initial certificate issuance fails (for example due to incorrect credentials or DNS propagation issues), the add-on will stop so the error can be corrected. Update the configuration and start the add-on again once the issue is resolved.

## Restarting dependent add-ons

Set `restart_addon_slug` when you want Home Assistant to restart another add-on immediately after certificates are renewed. The restart is triggered only if any certificate file actually changes, so dependent services are not bounced unnecessarily.

The slug is the identifier Home Assistant assigns to each add-on. Run `ha addons list` in the Home Assistant CLI and copy the value in the `slug` column for the add-on you want to restart.

Enter that slug (for example `core_nginx_proxy`) in the `restart_addon_slug` option for this add-on. Leave the field empty if no restart should be performed.

## Forcing a fresh issuance

Set `force_initial_request` to `true` when you need to discard the existing ACME account data or certificates and obtain a completely new set. On the next start the add-on deletes the contents of the configured `lego_path`, performs a full issuance run, and then resumes normal scheduled renewals. The directory is recreated before lego runs, so remember to set the option back to `false` once the fresh certificates have been obtained.
A few tips for configuring providers:

- Use the provider name exactly as lego documents it (for example `cloudflare`, `route53`, `inwx`).
- Add one `KEY=VALUE` entry per required environment variable. Every item is exported before lego runs.
- Avoid wrapping values in quotes; entered text is used as-is.

### Example: Cloudflare API token

```
dns_provider: cloudflare
dns_provider_env:
  - CLOUDFLARE_DNS_API_TOKEN=cf_example_token
```

### Example: INWX with shared secret

```
dns_provider: inwx
dns_provider_env:
  - INWX_USERNAME=12345
  - INWX_PASSWORD=secretpass
  - INWX_SHARED_SECRET=sharedsecret
```

Refer to the [lego DNS documentation](https://go-acme.github.io/lego/dns/index.html) for the exact set of variables required by your chosen provider.
