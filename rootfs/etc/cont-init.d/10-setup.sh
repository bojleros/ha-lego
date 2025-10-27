#!/usr/bin/with-contenv bashio
set -euo pipefail

CONFIG_PATH=/data/options.json
CONFIG_ENV_FILE=/var/run/lego-config.env
export CONFIG_PATH

sanitize_optional() {
    local value="$1"
    if [ -z "${value}" ] || [ "${value}" = "null" ]; then
        echo ""
    else
        echo "${value}"
    fi
}

bashio::log.info "Validating addon configuration"

if ! bashio::config.has_value 'domains'; then
    bashio::exit.nok "Option 'domains' must be configured"
fi

DOMAINS_LENGTH=$(bashio::config 'domains | length')

if [ ${DOMAINS_LENGTH} -eq 0 ]; then
    bashio::exit.nok "Option 'domains' must have at least one domain"
fi

if ! bashio::config.has_value 'email'; then
    bashio::exit.nok "Option 'email' must be configured"
fi

if ! bashio::config.has_value 'inwx_username'; then
    bashio::exit.nok "Option 'inwx_username' must be configured"
fi

if ! bashio::config.has_value 'inwx_password'; then
    bashio::exit.nok "Option 'inwx_password' must be configured"
fi

EMAIL=$(bashio::config 'email')
LEGO_PATH=$(sanitize_optional "$(bashio::config 'lego_path')")
if [ -z "${LEGO_PATH}" ]; then
    LEGO_PATH="/data/lego"
fi

CRON_SCHEDULE=$(sanitize_optional "$(bashio::config 'cron_schedule')")
if [ -z "${CRON_SCHEDULE}" ]; then
    CRON_SCHEDULE="0 3 * * *"
fi

KEY_TYPE=$(sanitize_optional "$(bashio::config 'key_type')")
if [ -z "${KEY_TYPE}" ]; then
    KEY_TYPE="rsa2048"
fi

RENEW_DAYS=$(sanitize_optional "$(bashio::config 'renew_days')")
if [ -z "${RENEW_DAYS}" ]; then
    RENEW_DAYS=30
fi

STAGING=$(sanitize_optional "$(bashio::config 'staging')")
if [ -z "${STAGING}" ]; then
    STAGING="false"
fi

RESTART_ADDON_SLUG=$(sanitize_optional "$(bashio::config 'restart_addon_slug')")
if [ -n "${RESTART_ADDON_SLUG}" ]; then
    bashio::log.info "Configured to restart add-on after certificate updates: ${RESTART_ADDON_SLUG}"
fi

FORCE_INITIAL_REQUEST=$(sanitize_optional "$(bashio::config 'force_initial_request')")
if [ -z "${FORCE_INITIAL_REQUEST}" ]; then
    FORCE_INITIAL_REQUEST="false"
fi
if bashio::var.true "${FORCE_INITIAL_REQUEST}"; then
    bashio::log.warning "Force initial request enabled; existing lego state will be removed on startup"
fi

INWX_USERNAME=$(bashio::config 'inwx_username')
INWX_PASSWORD=$(bashio::config 'inwx_password')
INWX_SHARED_SECRET=$(sanitize_optional "$(bashio::config 'inwx_shared_secret')")
INWX_TOTP=$(sanitize_optional "$(bashio::config 'inwx_totp')")

mkdir -p "${LEGO_PATH}"
chmod 700 "${LEGO_PATH}"

mkdir -p "$(dirname "${CONFIG_ENV_FILE}")"
{
    printf 'EMAIL=%q\n' "${EMAIL}"
    printf 'KEY_TYPE=%q\n' "${KEY_TYPE}"
    printf 'LEGO_PATH=%q\n' "${LEGO_PATH}"
    printf 'RENEW_DAYS=%q\n' "${RENEW_DAYS}"
    printf 'STAGING=%q\n' "${STAGING}"
    printf 'INWX_USERNAME=%q\n' "${INWX_USERNAME}"
    printf 'INWX_PASSWORD=%q\n' "${INWX_PASSWORD}"
    printf 'INWX_SHARED_SECRET=%q\n' "${INWX_SHARED_SECRET}"
    printf 'INWX_TOTP=%q\n' "${INWX_TOTP}"
    printf 'RESTART_ADDON_SLUG=%q\n' "${RESTART_ADDON_SLUG}"
    printf 'FORCE_INITIAL_REQUEST=%q\n' "${FORCE_INITIAL_REQUEST}"
    printf 'DOMAINS=('
    if [ "$DOMAINS_LENGTH" -gt 0 ]; then
        printf '\n'
        # Iterate through array elements by index
        for i in $(seq 0 $((DOMAINS_LENGTH - 1))); do
            domain=$(bashio::config "domains[${i}]")
            bashio::log.info "Parsing domain ${i}: ${domain}"
            printf '  %q\n' "${domain}"
        done
    fi
    printf ')\n'
} > "${CONFIG_ENV_FILE}"
chmod 600 "${CONFIG_ENV_FILE}"

cat > /etc/crontabs/root <<EOF
SHELL=/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin
${CRON_SCHEDULE} /bin/sh -c '/usr/local/bin/lego-renew.sh >> /proc/1/fd/1 2>&1'
EOF
chmod 600 /etc/crontabs/root

bashio::log.info "Cron schedule configured: ${CRON_SCHEDULE}"

bashio::log.info "Running initial lego task"
if ! /usr/local/bin/lego-renew.sh --auto; then
    bashio::exit.nok "Initial certificate issuance or renewal failed"
fi
