#!/bin/sh
# Stage the working copy into the i-MSCP panel's plugins directory.
#
# The repository is exported into the Vagrant box over virtiofs, which carries
# the host uid. The panel runs as vu2000, so the tree is copied rather than
# mounted in place.
#
# Run inside the box:  sudo /usr/local/src/imscp-apache-cache/tools/deploy.sh

set -e

PLUGIN=SGW_ApacheCache
SRC=$(cd "$(dirname "$0")/.." && pwd)
DEST=/var/www/imscp/gui/plugins/$PLUGIN

[ "$(id -u)" -eq 0 ] || { echo "$0: must be run as root" >&2; exit 1; }

rsync -a --delete \
    --exclude '.git' --exclude 'test' --exclude 'tools' --exclude 'Vagrantfile' \
    "$SRC/" "$DEST/"

chown -R vu2000:vu2000 "$DEST"
find "$DEST" -type d -exec chmod 0750 {} +
find "$DEST" -type f -exec chmod 0640 {} +

# The panel's PHP-FPM keeps opcached bytecode, so a redeployed file is
# otherwise ignored until the pool recycles.
systemctl restart imscp_panel

echo "Deployed $SRC -> $DEST"
echo "Now update the plugin list in the panel: System tools / Plugin management."
