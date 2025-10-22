#!/usr/bin/with-contenv bash
set -euo pipefail

umask 077

LEGO_BIN=${LEGO_BIN:-/usr/bin/lego}
CONFIG_ENV_FILE=${CONFIG_ENV_FILE:-/var/run/lego-config.env}
ACME_STAGING_ENDPOINT="https://acme-staging-v02.api.letsencrypt.org/directory"

info() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_file() {
    local path="$1"
    local description="$2"
    if [ ! -f "$path" ]; then
        warn "Expected ${description} at ${path} not found"
        return 1
    fi
    return 0
}

require_directory() {
    local path="$1"
    local description="$2"
    if [ ! -d "$path" ]; then
        error "${description} directory ${path} is not accessible"
    fi
}

load_config() {
    if [ ! -f "$CONFIG_ENV_FILE" ]; then
        error "Configuration environment file ${CONFIG_ENV_FILE} not found"
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_ENV_FILE"

    EMAIL=${EMAIL:-}
    if [ -z "${EMAIL}" ]; then
        error "Configuration option 'email' must be set"
    fi

    if ! declare -p DOMAINS >/dev/null 2>&1; then
        DOMAINS=()
    fi

    if [ "${#DOMAINS[@]}" -eq 0 ]; then
        error "Configuration option 'domains' must include at least one entry"
    fi

    KEY_TYPE=${KEY_TYPE:-rsa2048}
    LEGO_PATH=${LEGO_PATH:-/data/lego}
    RENEW_DAYS=${RENEW_DAYS:-30}
    STAGING=${STAGING:-false}

    INWX_USERNAME=${INWX_USERNAME:-}
    INWX_PASSWORD=${INWX_PASSWORD:-}
    INWX_SHARED_SECRET=${INWX_SHARED_SECRET:-}
    INWX_TOTP=${INWX_TOTP:-}

    if [ -z "${INWX_USERNAME}" ]; then
        error "Configuration option 'inwx_username' must be set"
    fi
    if [ -z "${INWX_PASSWORD}" ]; then
        error "Configuration option 'inwx_password' must be set"
    fi
}

build_command() {
    LEGO_CMD=("${LEGO_BIN}" "--path" "${LEGO_PATH}" "--email" "${EMAIL}" "--accept-tos" "--dns" "inwx" "--key-type" "${KEY_TYPE}")

    if [ "${STAGING}" = "true" ]; then
        LEGO_CMD+=("--server" "${ACME_STAGING_ENDPOINT}")
    fi

    for domain in "${DOMAINS[@]}"; do
        LEGO_CMD+=("--domains" "${domain}")
    done
}

export_dns_credentials() {
    export INWX_USERNAME
    export INWX_PASSWORD

    if [ -n "${INWX_SHARED_SECRET}" ]; then
        export INWX_SHARED_SECRET
    else
        unset INWX_SHARED_SECRET || true
    fi

    if [ -n "${INWX_TOTP}" ]; then
        export INWX_TOTP_PIN="${INWX_TOTP}"
    else
        unset INWX_TOTP_PIN || true
    fi
}

sanitize_domain() {
    local domain="$1"
    echo "${domain//\*/_}"
}

copy_certificates() {
    require_directory "/ssl" "Home Assistant SSL"

    for domain in "${DOMAINS[@]}"; do
        local sanitized
        sanitized=$(sanitize_domain "${domain}")
        local base="${LEGO_PATH}/certificates/${sanitized}"

        if require_file "${base}.crt" "certificate" && require_file "${base}.key" "private key"; then
            install -m 644 "${base}.crt" "/ssl/${sanitized}.crt"
            install -m 640 "${base}.key" "/ssl/${sanitized}.key"

            if [ -f "${base}.issuer.crt" ]; then
                install -m 644 "${base}.issuer.crt" "/ssl/${sanitized}.issuer.crt"
                local tmp
                tmp=$(mktemp)
                cat "${base}.crt" "${base}.issuer.crt" > "${tmp}"
                install -m 644 "${tmp}" "/ssl/${sanitized}.fullchain.pem"
                rm -f "${tmp}"
            else
                install -m 644 "${base}.crt" "/ssl/${sanitized}.fullchain.pem"
            fi

            info "Updated certificate assets for ${domain}"
        else
            warn "Skipping copy for ${domain}; certificate files missing"
        fi
    done
}

ensure_lego_path() {
    mkdir -p "${LEGO_PATH}/certificates"
    chmod 700 "${LEGO_PATH}"
}

run_command() {
    local action="$1"
    local primary_sanitized
    primary_sanitized=$(sanitize_domain "${DOMAINS[0]}")
    local cert_path="${LEGO_PATH}/certificates/${primary_sanitized}.crt"
    local key_path="${LEGO_PATH}/certificates/${primary_sanitized}.key"

    case "${action}" in
        run)
            info "Running initial certificate request for ${DOMAINS[*]}"
            "${LEGO_CMD[@]}" run
            ;;
        renew)
            info "Renewing certificates (threshold ${RENEW_DAYS} days) for ${DOMAINS[*]}"
            "${LEGO_CMD[@]}" renew --days "${RENEW_DAYS}"
            ;;
        auto)
            if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
                info "No existing certificate found; starting initial issuance for ${DOMAINS[*]}"
                "${LEGO_CMD[@]}" run
            else
                info "Existing certificate detected; attempting renewal (threshold ${RENEW_DAYS} days)"
                "${LEGO_CMD[@]}" renew --days "${RENEW_DAYS}"
            fi
            ;;
        *)
            error "Unknown action '${action}'"
            ;;
    esac
}

main() {
    load_config
    ensure_lego_path
    export_dns_credentials
    build_command

    local action="auto"
    if [ "${#}" -gt 0 ]; then
        case "$1" in
            --run)
                action="run"
                ;;
            --renew)
                action="renew"
                ;;
            --auto)
                action="auto"
                ;;
            *)
                error "Unsupported argument '$1'. Use --run, --renew, or --auto."
                ;;
        esac
    fi

    run_command "${action}"
    copy_certificates
}

main "$@"
