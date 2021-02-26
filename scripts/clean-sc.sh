#!/bin/bash

echo "WARNING:"
echo "This script will remove compliant kubernetes apps from your service cluster."
echo "Do you want to continue (y/N): "
read -r reply
if [[ ${reply} != "y" ]]; then
    exit 1
fi

here="$(dirname "$(readlink -f "$0")")"

# Destroy all helm releases
"${here}/.././bin/ck8s" ops helmfile sc destroy

# Clean up namespaces and any other resources left behind by the apps
"${here}/.././bin/ck8s" ops kubectl sc delete ns cert-manager dex elastic-system harbor fluentd influxdb-prometheus ingress-nginx monitoring velero

# Remove any lingering persistent volumes
"${here}/.././bin/ck8s" ops kubectl sc delete pv --all

# Remove all added custom resource definitions
"${here}/.././bin/ck8s" ops kubectl sc delete -f bootstrap/crds/ --recursive
