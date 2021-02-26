#!/bin/bash

echo "WARNING:"
echo "This script will remove compliant kubernetes apps from your workload cluster."
echo "It will also remove any user namespaces managed by compliant kubernetes apps."
echo "Do you want to continue (y/N): "
read -r reply
if [[ ${reply} != "y" ]]; then
    exit 1
fi

SCRIPTS_PATH="$(dirname "$(readlink -f "$0")")"

#Destroy all helm releases
"${SCRIPTS_PATH}/.././bin/ck8s" ops helmfile wc destroy

#Clean up namespaces and any other resources left behind by the apps
"${SCRIPTS_PATH}/.././bin/ck8s" ops kubectl wc delete ns cert-manager falco fluentd gatekeeper gatekeeper-system ingress-nginx monitoring velero

#Remove any lingering persistent volumes
"${SCRIPTS_PATH}/.././bin/ck8s" ops kubectl wc delete pv --all

#Remove all added custom resource definitions
"${SCRIPTS_PATH}/.././bin/ck8s" ops kubectl wc delete -f bootstrap/crds/ --recursive
