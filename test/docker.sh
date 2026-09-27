#!/bin/sh
# Run test/run.sh inside the i-MSCP docker stack of the sibling i-MSCP checkout.
#
#   test/docker.sh [test/run.sh arguments]
#
# The stack mounts the directory holding the plugin checkouts at
# /var/www/imscp-plugins, so this checkout — a git worktree included — is
# already inside it; nothing is copied. See docker/README.md in i-MSCP.
#
# Environment:
#   IMSCP_DIR        the i-MSCP checkout, default ../imscp beside this repository
#   IMSCP_CONTAINER  the container, default COMPOSE_PROJECT_NAME from its docker/.env
#   SGW_NETWORK_TESTS, SGW_DESTRUCTIVE_TESTS, PHP_BIN, PROVE_ARGS are passed on.

set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
# The main checkout, which is where the sibling i-MSCP checkout sits beside,
# even when this is a worktree somewhere under it.
main="$(cd "$here" && cd "$(git rev-parse --git-common-dir)/.." && pwd)"
imscp="${IMSCP_DIR:-$(dirname "$main")/imscp}"

setting() {
    [ -f "$imscp/docker/.env" ] || return 0
    sed -nE "s/^$1=\"?([^\"]*)\"?$/\1/p" "$imscp/docker/.env" | tail -n 1
}

container="${IMSCP_CONTAINER:-$(setting COMPOSE_PROJECT_NAME)}"
container="${container:-imscp-dev}"

# PLUGINS_SRC_ROOT is relative to the docker/ directory, as compose reads it.
src="$(setting PLUGINS_SRC_ROOT)"
src="$(cd "$imscp/docker" && cd "${src:-../..}" && pwd)"
case "$here" in
    "$src"/*) path="/var/www/imscp-plugins/${here#"$src"/}" ;;
    *) echo "$0: $here is not under $src, which the stack mounts" >&2; exit 2 ;;
esac

docker exec \
    -e SGW_NETWORK_TESTS="${SGW_NETWORK_TESTS:-}" \
    -e SGW_DESTRUCTIVE_TESTS="${SGW_DESTRUCTIVE_TESTS:-}" \
    -e PHP_BIN="${PHP_BIN:-php}" \
    -e PROVE_ARGS="${PROVE_ARGS:-}" \
    -w "$path" "$container" sh test/run.sh "$@"
