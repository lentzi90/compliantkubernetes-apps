#!/bin/bash

SCRIPTS_PATH="$(dirname "$(readlink -f "$0")")"

#Destroy all helm releases
"${SCRIPTS_PATH}/.././bin/ck8s" ops helmfile sc destroy

#Clean up namespaces and any other resources left behind by the apps
"${SCRIPTS_PATH}/.././bin/ck8s" ops kubectl sc delete ns cert-manager dex elastic-system harbor fluentd influxdb-prometheus ingress-nginx monitoring velero

#Remove any lingering persistent volumes
"${SCRIPTS_PATH}/.././bin/ck8s" ops kubectl sc delete pv --all

#Remove all added custom resource definitions
"${SCRIPTS_PATH}/.././bin/ck8s" ops kubectl sc delete -f bootstrap/crds/ --recursive
