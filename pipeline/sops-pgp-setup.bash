#!/usr/bin/env bash

set -eu -o pipefail

passphrase=only4testing

read -r -d '' key <<EOF || true
-----BEGIN PGP PRIVATE KEY BLOCK-----

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
mhPjtPNR4w==
=iXC8
-----END PGP PRIVATE KEY BLOCK-----
EOF

echo "${passphrase}" | \
    gpg --pinentry-mode loopback --passphrase-fd 0 --import \
    <(echo "${key}")

echo allow-preset-passphrase > ~/.gnupg/gpg-agent.conf
gpg-connect-agent reloadagent /bye

keys=$(gpg --list-keys --with-colons --with-keygrip)
keygrip=$(echo "${keys}" | awk -F: '$1 == "grp" {print $10;}' | tail -n1)

echo "${passphrase}" | \
    /usr/lib/gnupg2/gpg-preset-passphrase --preset "${keygrip}"
