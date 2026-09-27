#!/bin/sh
# Run the plugin's test suite. The single entry point for people and for CI.
#
# Runs on a host where i-MSCP is installed — the docker stack in the sibling
# i-MSCP checkout, or the CI image built from it — as root. From a development
# machine, test/docker.sh runs this inside the docker stack for you.
#
#   test/run.sh                         everything that is safe on a shared host
#   test/run.sh test/backend/40-run.t   just the named files
#
# Environment:
#   SGW_NETWORK_TESTS=1      also query the public DNS (90-dns-lookup.t)
#   SGW_DESTRUCTIVE_TESTS=1  also install certbot on this host (95-install.t);
#                            for a throwaway container only
#   IMSCP_ENGINE_DIR         the i-MSCP engine, default /var/www/imscp/engine
#   PHP_BIN                  the PHP to lint and test with, default php
#   PROVE_ARGS               extra prove options, e.g. "--formatter TAP::Formatter::JUnit"
#
# The exit status is non-zero when any test fails, which is all CI needs.

set -u

cd "$(dirname "$0")/.." || exit 2

[ "$(id -u)" -eq 0 ] || { echo "$0: must be run as root" >&2; exit 2; }

if [ $# -gt 0 ]; then
    backend="$(printf '%s\n' "$@" | grep -v '^test/frontend/' || true)"
    frontend="$(printf '%s\n' "$@" | grep '^test/frontend/' || true)"
else
    backend=test/backend
    frontend=test/frontend
fi

rc=0
if [ -n "$backend" ]; then
    # shellcheck disable=SC2086
    prove --verbose --timer ${PROVE_ARGS:-} $backend || rc=1
fi
if [ -n "$frontend" ]; then
    # shellcheck disable=SC2086
    prove --verbose --timer --exec "${PHP_BIN:-php}" --ext .t ${PROVE_ARGS:-} $frontend || rc=1
fi
exit $rc
