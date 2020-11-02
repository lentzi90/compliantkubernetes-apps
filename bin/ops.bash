#!/usr/bin/env bash

# CK8S operator actions.

set -eu

here="$(dirname "$(readlink -f "$0")")"

# shellcheck disable=SC1090
source "${here}/common.bash"

: "${secrets[kube_config_sc]:?Missing service cluster kubeconfig}"
: "${secrets[kube_config_wc]:?Missing workload cluster kubeconfig}"

usage() {
    echo "Usage: kubectl <wc|sc> ..." >&2
    echo "       helmfile <wc|sc> ..." >&2
    exit 1
}

# Run arbitrary kubectl commands as cluster admin.
ops_kubectl() {
    case "${1}" in
        sc) kubeconfig="${secrets[kube_config_sc]}" ;;
        wc) kubeconfig="${secrets[kube_config_wc]}" ;;
        *) usage ;;
    esac
    shift
    with_kubeconfig "${kubeconfig}" kubectl "${@}"
}

# Run arbitrary Helmfile commands as cluster admin.
ops_helmfile() {
    config_load "$1"

    case "${1}" in
        sc)
            cluster="service_cluster"
            kubeconfig="${secrets[kube_config_sc]}"
        ;;
        wc)
            cluster="workload_cluster"
            kubeconfig="${secrets[kube_config_wc]}"
        ;;
        *) usage ;;
    esac

    shift

    export CONFIG_PATH="${CK8S_CONFIG_PATH}"

    # TODO: Get rid of this.
    # shellcheck disable=SC1090
    source "${scripts_path:?Missing scripts path}/post-infra-common.sh" \
        "${config[infrastructure_file]:?Missing infrastructure file}"

    with_kubeconfig "${kubeconfig}" \
        helmfile -f "${here}/../helmfile/" -e ${cluster} "${@}"
}

case "${1}" in
    kubectl)
        shift
        ops_kubectl "${@}"
    ;;
    helmfile)
        shift
        ops_helmfile "${@}"
    ;;
    *) usage ;;
esac
