#!/usr/bin/env bash
# Build telegraf-light .deb packages.
#
#   ./build-deb.sh [OUT_DIR] [arch...]     # default: ./out/deb, arm64
#
# Env: TELEGRAF_VERSION, PKG_REV (default: version.env), plus build.sh env.
set -euo pipefail
umask 022

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/version.env"
export TELEGRAF_VERSION PKG_REV

DEB_DIR=${1:-$HERE/out/deb}
shift || true
ARCHS=("$@")
[ ${#ARCHS[@]} -gt 0 ] || ARCHS=(arm64)

export OUT_DIR=${OUT_DIR:-$HERE/out}
"$HERE/build.sh" "${ARCHS[@]}"

VERSION=$TELEGRAF_VERSION-$PKG_REV
SRC=$OUT_DIR/src
mkdir -p "$DEB_DIR"

for ARCH in "${ARCHS[@]}"; do
    ROOT=$(mktemp -d)
    chmod 755 "$ROOT"
    trap 'rm -rf "$ROOT"' EXIT

    install -D -m 755 "$OUT_DIR/$ARCH/telegraf" "$ROOT/usr/bin/telegraf"
    install -D -m 644 "$SRC/scripts/telegraf.service" "$ROOT/usr/lib/systemd/system/telegraf.service"
    install -D -m 644 "$SRC/scripts/telegraf.service" "$ROOT/usr/share/telegraf-light/telegraf.service"
    install -D -m 644 "$HERE/debian/telegraf.conf" "$ROOT/usr/share/telegraf-light/telegraf.conf"
    install -D -m 644 "$HERE/plugins.txt" "$ROOT/usr/share/doc/telegraf-light/plugins.txt"
    {
        echo "Telegraf $TELEGRAF_VERSION, https://github.com/influxdata/telegraf"
        echo "Packaging: https://github.com/lab240/telegraf-ligth"
        echo
        cat "$SRC/LICENSE"
    } > "$ROOT/usr/share/doc/telegraf-light/copyright"
    install -d "$ROOT/etc/telegraf/telegraf.d"

    install -d "$ROOT/DEBIAN"
    for f in preinst postinst prerm postrm; do
        install -m 755 "$HERE/debian/$f" "$ROOT/DEBIAN/$f"
    done
    sed -e "s/@VERSION@/$VERSION/" -e "s/@UPSTREAM@/$TELEGRAF_VERSION/g" -e "s/@ARCH@/$ARCH/" \
        -e "s/@SIZE@/$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)/" \
        "$HERE/debian/control.in" > "$ROOT/DEBIAN/control"

    DEB=$DEB_DIR/telegraf-light_${VERSION}_$ARCH.deb
    dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$DEB" >/dev/null
    rm -rf "$ROOT"
    trap - EXIT
    ls -l "$DEB"
done
