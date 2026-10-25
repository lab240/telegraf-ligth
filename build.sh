#!/usr/bin/env bash
# Build Telegraf with the plugins from plugins.txt.
#
#   ./build.sh                 # arm64 → out/arm64/telegraf
#   ./build.sh arm64 amd64
#
# Env:
#   TELEGRAF_VERSION  upstream tag without "v" (default: version.env)
#   OUT_DIR           output dir (default: ./out)
#   GO_IMAGE          docker image used when go is not installed
#                     (default: golang:1.27-trixie)
#
# go older than the one in Telegraf's go.mod downloads the right toolchain
# itself (GOTOOLCHAIN=auto).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/version.env"
OUT_DIR=${OUT_DIR:-$HERE/out}
GO_IMAGE=${GO_IMAGE:-golang:1.27-trixie}

ARCHS=("$@")
[ ${#ARCHS[@]} -gt 0 ] || ARCHS=(arm64)

mkdir -p "$OUT_DIR"
OUT_DIR=$(realpath "$OUT_DIR")

if ! command -v go >/dev/null; then
    echo "go not found, building in $GO_IMAGE"
    exec docker run --rm -e TELEGRAF_VERSION -e PKG_REV -e OUT_DIR=/out \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        -v "$HERE:/build:ro" -v "$OUT_DIR:/out" \
        -v telegraf-light-gomod:/go/pkg/mod -v telegraf-light-gocache:/root/.cache/go-build \
        "$GO_IMAGE" /build/build.sh "${ARCHS[@]}"
fi

TAGS=custom,$(grep -vE '^\s*(#|$)' "$HERE/plugins.txt" | paste -sd,)
SRC=$OUT_DIR/src

if [ "$(git -C "$SRC" describe --tags 2>/dev/null)" != "v$TELEGRAF_VERSION" ]; then
    rm -rf "$SRC"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "v$TELEGRAF_VERSION" \
        https://github.com/influxdata/telegraf.git "$SRC"
fi

COMMIT=$(git -C "$SRC" rev-parse --short HEAD)
PKG=github.com/influxdata/telegraf/internal
LDFLAGS="-s -w -X $PKG.Version=$TELEGRAF_VERSION -X $PKG.Commit=$COMMIT -X $PKG.Branch=HEAD"

echo "telegraf $TELEGRAF_VERSION ($COMMIT), tags: $TAGS"

for ARCH in "${ARCHS[@]}"; do
    mkdir -p "$OUT_DIR/$ARCH"
    (cd "$SRC" && GOTOOLCHAIN=${GOTOOLCHAIN:-auto} CGO_ENABLED=0 GOOS=linux GOARCH=$ARCH \
        go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" \
        -o "$OUT_DIR/$ARCH/telegraf" ./cmd/telegraf)
    ls -l "$OUT_DIR/$ARCH/telegraf"
done

if [ -n "${HOST_UID:-}" ]; then
    chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$OUT_DIR"
fi
