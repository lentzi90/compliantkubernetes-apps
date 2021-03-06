#!/bin/bash

# This file is not supposed to be executed on it's own, but rather is sourced
# by the other scripts in this path. It holds common paths and functions that
# are used throughout all of the scripts.

: "${CK8S_CONFIG_PATH:?Missing CK8S_CONFIG_PATH}"

CK8S_AUTO_APPROVE=${CK8S_AUTO_APPROVE:-"false"}

if [ "${SOPS_PGP_FP+x}" != "" ]; then
    echo "SOPS_PGP_FP is deprecated." >&2
    echo "Set CK8S_PGP_UID or CK8S_PGP_FP and run \`ck8s init\` to" \
         "generate a sops config file instead." >&2
    exit 1
fi

# Create CK8S_CONFIG_PATH if it does not exist and make it absolute
mkdir -p "${CK8S_CONFIG_PATH}"
CK8S_CONFIG_PATH=$(readlink -f "${CK8S_CONFIG_PATH}")
export CK8S_CONFIG_PATH

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
root_path="${here}/.."
config_defaults_path="${root_path}/config"
# TODO: these are used by sourced scripts.
# Should we export all "externally" used variables?
# shellcheck disable=SC2034
scripts_path="${root_path}/scripts"
# shellcheck disable=SC2034
pipeline_path="${root_path}/pipeline"

sops_config="${CK8S_CONFIG_PATH}/.sops.yaml"
state_path="${CK8S_CONFIG_PATH}/.state"
ssh_path="${CK8S_CONFIG_PATH}/ssh"

declare -A config
declare -A secrets

config["config_file"]="${CK8S_CONFIG_PATH}/config.sh"
config["config_file_wc"]="${CK8S_CONFIG_PATH}/wc-config.yaml"
config["config_file_sc"]="${CK8S_CONFIG_PATH}/sc-config.yaml"

secrets["secrets_file"]="${CK8S_CONFIG_PATH}/secrets.yaml"
secrets["s3cfg_file"]="${state_path}/s3cfg.ini"

secrets["kube_config_sc"]="${state_path}/kube_config_sc.yaml"
secrets["kube_config_wc"]="${state_path}/kube_config_wc.yaml"

secrets["ssh_priv_key_sc"]="${ssh_path}/id_rsa_sc"
secrets["ssh_priv_key_wc"]="${ssh_path}/id_rsa_wc"

secrets["user_kubeconfig"]="${CK8S_CONFIG_PATH}/user/kubeconfig.yaml"

config["ssh_pub_key_sc"]="${secrets[ssh_priv_key_sc]}.pub"
config["ssh_pub_key_wc"]="${secrets[ssh_priv_key_wc]}.pub"

log_info() {
    echo -e "[\e[34mck8s\e[0m] ${*}" 1>&2
}

log_warning() {
    echo -e "[\e[33mck8s\e[0m] ${*}" 1>&2
}

log_error() {
    echo -e "[\e[31mck8s\e[0m] ${*}" 1>&2
}

version_get() {
    pushd "${root_path}" > /dev/null || exit 1
    git describe --tags --abbrev=0 HEAD | sed 's/^v//'
    popd > /dev/null || exit 1
}

# Check if the config version matches the current CK8S version.
# TODO: Simple hack to make sure version matches, we need to have a proper way
#       of making sure that the version is supported in the future.
validate_version() {
    version=$(version_get)
    if [[ "${1}" == "sc" ]]; then
        file="${config[config_file_sc]}"
    elif [[ "${1}" == "wc" ]]; then
        file="${config[config_file_wc]}"
    else
      echo log_error "Error: usage validate_version <wc|sc>"
      exit 1
    fi
    ck8s_version=$(yq r "${file}" 'global.ck8sVersion')
    if [[ -z "$ck8s_version" ]]; then
        log_error "ERROR: global.ck8sVersion is not set in ${file}"
        exit 1
    fi
    if [ "${ck8s_version}" != "any" ] \
        && [ "${version}" != "${ck8s_version}" ]; then
        log_error "ERROR: Version mismatch!"
        log_error "Config version: ${ck8s_version}"
        log_error "CK8S version: ${version}"
        exit 1
    fi
}

# Check if the cloud provider is supported.
validate_cloud() {
    if [ "${1}" != "exoscale" ] &&
       [ "${1}" != "safespring" ] &&
       [ "${1}" != "citycloud" ] &&
       [ "${1}" != "baremetal" ] &&
       [ "${1}" != "aws" ]; then
        log_error "ERROR: Unsupported cloud provider: ${1}"
        exit 1
    fi
}

# Make sure that all required configuration options are set in the config.
# TODO: Simple hack to make sure configuration is valid, we need to have a
#       proper way of making sure that the configuration is valid in the
#       future.
validate_config() {
    log_info "Validating $1 config"
    validate() {
        if [[ ! -f "${1}" ]]; then
            log_error "ERROR: could not find file $1"
            exit 1
        fi
        if [[ ! $1 =~ ^.*\.(yaml|yml) ]]; then
            log_error "ERROR: file $1 must be a yaml file"
            exit 1
        fi
        if [[ ! -f "${2}" ]]; then
          log_error "could not find file $2"
          exit 1
        fi
        if [[ ! $2 =~ ^.*\.(yaml|yml) ]]; then
            log_error "ERROR: file $2 must be a yaml file"
            exit 1
        fi

        file="${1}"
        options=$(yq r -p p "${2}" '**')
        # Loop all lines in $2 and warns if same option is not
        # available in $1
        maybe_exit="false"
        for opt in ${options}; do
            value=$(yq r "${file}" "${opt}")
            if [[ -z "$value" ]]; then
                log_warning "WARN: ${opt} is not set in ${file}"
                maybe_exit="true"
            fi
        done

        if ${maybe_exit} && ! ${CK8S_AUTO_APPROVE}; then
            echo -n -e "[\e[34mck8s\e[0m] Do you want to abort? (y/n): " 1>&2
            read -r reply
            if [[ "${reply}" == "y" ]]; then
                exit 1
            fi
        fi
    }

    if [[ $1 == "sc" ]]; then
        validate "${config[config_file_sc]}" "${config_defaults_path}/config/sc-config.yaml"

        validate "${secrets[secrets_file]}" "${config_defaults_path}/secrets/sc-secrets.yaml"

        if [[ $CLOUD_PROVIDER == "citycloud" ]]; then
            validate "${config[config_file_sc]}" "${config_defaults_path}/config/citycloud.yaml"
        fi
    elif [[ $1 == "wc" ]]; then
        validate "${config[config_file_wc]}" "${config_defaults_path}/config/wc-config.yaml"
        validate "${secrets[secrets_file]}" "${config_defaults_path}/secrets/wc-secrets.yaml"
    else
        log_error "Error: usage validate_config <sc|wc>"
        exit 1
    fi

    if [[ $CLOUD_PROVIDER == "citycloud" ]]; then
        validate "${secrets[secrets_file]}" "${config_defaults_path}/secrets/citycloud.yaml"
    fi

}

validate_sops_config() {
    if [ ! -f "${sops_config}" ]; then
        log_error "ERROR: SOPS config not found: ${sops_config}"
        exit 1
    fi

    rule_count=$(yq r - --length creation_rules < "${sops_config}")
    if [ "${rule_count:-0}" -gt 1 ]; then
        log_error "ERROR: SOPS config has more than one creation rule."
        exit 1
    fi

    fingerprints=$(yq r - 'creation_rules[0].pgp' < "${sops_config}")
    if ! [[ "${fingerprints}" =~ ^[A-Z0-9,' ']+$ ]]; then
        log_error "ERROR: SOPS config contains no or invalid PGP keys."
        log_error "fingerprints=${fingerprints}"
        log_error "Fingerprints must be uppercase and separated by colon."
        log_error "Delete or edit the SOPS config to fix the issue"
        log_error "SOPS config: ${sops_config}"
        exit 1
    fi
}

# Load and validate all configuration options from the config path.
config_load() {
    if [[ "${1}" == "sc" ]]; then
        CLOUD_PROVIDER=$(yq r -e "${config[config_file_sc]}" 'global.cloudProvider')
        export CLOUD_PROVIDER
    elif [[ "${1}" == "wc" ]]; then
        CLOUD_PROVIDER=$(yq r -e "${config[config_file_wc]}" 'global.cloudProvider')
        export CLOUD_PROVIDER
    else
      echo log_error "Error: usage config_load <wc|sc>"
      exit 1
    fi

    validate_version "$1"
    validate_cloud "${CLOUD_PROVIDER}"
    validate_config "$1"
    validate_sops_config
}

# Normally a signal handler can only run one command. Use this to be able to
# add multiple traps for a single signal.
append_trap() {
    cmd="${1}"
    signal="${2}"

    if [ "$(trap -p "${signal}")" = "" ]; then
        # shellcheck disable=SC2064
        trap "${cmd}" "${signal}"
        return
    fi

    previous_trap_cmd() { printf '%s\n' "$3"; }

    new_trap() {
        eval "previous_trap_cmd $(trap -p "${signal}")"
        printf '%s\n' "${cmd}"
    }

    # shellcheck disable=SC2064
    trap "$(new_trap)" "${signal}"
}

# Write PGP fingerprints to SOPS config
sops_config_write_fingerprints() {
    yq n 'creation_rules[0].pgp' "${1}" > "${sops_config}" || \
      (log_error "Failed to write fingerprints" && rm "${sops_config}" && exit 1)
}

# Encrypt stdin to file. If the file already exists it's overwritten.
sops_encrypt_stdin() {
    sops --config "${sops_config}" -e --input-type "${1}" \
         --output-type "${1}" /dev/stdin > "${2}"
}

# Encrypt a file in place.
sops_encrypt() {
    # https://github.com/mozilla/sops/issues/460
    if grep -F -q 'sops:' "${1}" || \
        grep -F -q '"sops":' "${1}" || \
        grep -F -q '[sops]' "${1}" || \
        grep -F -q 'sops_version=' "${1}"; then
        log_info "Already encrypted ${1}"
        return
    fi

    log_info "Encrypting ${1}"

    sops --config "${sops_config}" -e -i "${1}"
}

# Check that a file exists and is actually encrypted using SOPS.
sops_decrypt_verify() {
    if [ ! -f "${1}" ]; then
        log_error "ERROR: Encrypted file not found: ${1}"
        exit 1
    fi

    # https://github.com/mozilla/sops/issues/460
    if ! grep -F -q 'sops:' "${1}" && \
       ! grep -F -q '"sops":' "${1}" && \
       ! grep -F -q '[sops]' "${1}" && \
       ! grep -F -q 'sops_version=' "${1}"; then
        log_error "NOT ENCRYPTED: ${1}"
        exit 1
    fi
}

# Decrypt a file in place and encrypt it again at exit.
#
# Run this inside a sub-shell to encrypt the file again as soon as it's no
# longer used. For example:
# (
#   sops_decrypt config
#   command --config config
# )
# TODO: This is bad since it makes the decrypted secrets touch the filesystem.
#       We should try to remove this asap.
sops_decrypt() {
    log_info "Decrypting ${1}"

    sops_decrypt_verify "${1}"

    sops --config "${sops_config}" -d -i "${1}"
    append_trap "sops_encrypt ${1}" EXIT
}

# Temporarily decrypts a file and runs a command that can read it once.
sops_exec_file() {
    sops_decrypt_verify "${1}"

    sops --config "${sops_config}" exec-file "${1}" "${2}"
}

# The same as sops_exec_file except the decrypted file is written as a normal
# file on disk while it's being used.
# This should only be used if absolutely necessary, for example where the
# decrypted file needs to be read more than once.
# TODO: Try to eliminate this in the future.
sops_exec_file_no_fifo() {
    sops_decrypt_verify "${1}"

    sops --config "${sops_config}" exec-file --no-fifo "${1}" "${2}"
}

# Temporarily decrypts a file and loads the content as environment variables
# that will only be available to a command.
sops_exec_env() {
    sops_decrypt_verify "${1}"

    sops --config "${sops_config}" exec-env "${1}" "${2}"
}

# Run a command with the secrets config options available as environment
# variables.
with_config_secrets() {
    sops_decrypt_verify "${secrets[secrets_file]}"

    sops_exec_env "${secrets[secrets_file]}" "${*}"
}


# Run a command with KUBECONFIG set to a temporarily decrypted file.
with_kubeconfig() {
    kubeconfig="${1}"
    shift
    # TODO: Can't use a FIFO since we can't know that the kubeconfig is not
    #       read multiple times. Let's try to eliminate the need for writing
    #       the kubeconfig to disk in the future.
    sops_exec_file_no_fifo "${kubeconfig}" 'KUBECONFIG="{}" '"${*}"
}

# Runs a command with S3COMMAND_CONFIG_FILE set to a temporarily decrypted
# file.
with_s3cfg() {
    s3cfg="${1}"
    shift
    # TODO: Can't use a FIFO since the s3cfg is read mulitiple times when a
    #       bucket needs to be created.
    sops_exec_file_no_fifo "${s3cfg}" 'S3COMMAND_CONFIG_FILE="{}" '"${*}"
}
