#!/usr/bin/env bash
# Install the built package into a systemd container and check it:
# fresh install, metrics, replacing InfluxData's telegraf, purge.
#
#   test/test-install.sh [noble|trixie]     # needs out/deb/*_arm64.deb
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
RELEASE=${1:-noble}
NAME=telegraf-light-test-$RELEASE
IMAGE=telegraf-light-sysd:$RELEASE
INFLUX_KEY_FPR=24C975CBA61A024EE1B631787C3D57159FC2F927

case $RELEASE in
    noble) BASE=ubuntu:24.04 ;;
    trixie) BASE=debian:trixie ;;
    *) echo "Unsupported release: $RELEASE" >&2; exit 1 ;;
esac

docker build -q -t "$IMAGE" - >/dev/null <<EOF
FROM $BASE
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus ca-certificates curl gpg && rm -rf /var/lib/apt/lists/*
CMD ["/sbin/init"]
EOF

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --privileged --cgroupns=host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
    -v "$HERE/out/deb:/pkgs:ro" "$IMAGE" >/dev/null
trap 'docker rm -f "$NAME" >/dev/null' EXIT

dx() { docker exec "$NAME" bash -c "$*"; }
apt_install() { dx "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $* >/dev/null"; }
fail() { echo "FAIL: $*"; exit 1; }

until dx 'systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"'; do sleep 1; done
dx 'apt-get update -qq'

echo "== fresh install"
apt_install /pkgs/telegraf-light_*_arm64.deb
dx 'telegraf --version; id telegraf; ls -l /etc/default/telegraf /etc/telegraf; systemctl is-enabled telegraf'
dx 'cmp -s /etc/telegraf/telegraf.conf /usr/share/telegraf-light/telegraf.conf' || fail "telegraf.conf not installed"

echo "== metrics (inputs.cpu, output file)"
dx 'cat > /etc/telegraf/telegraf.d/test.conf <<EOT
[[inputs.cpu]]
[[outputs.file]]
EOT'
# outputs.file is not in the build: Telegraf must refuse the config.
dx 'telegraf --test --config /etc/telegraf/telegraf.d/test.conf 2>&1 | grep -q "undefined but requested output: file"' ||
    fail "unknown plugin accepted"
dx 'printf "[[inputs.cpu]]\n" > /etc/telegraf/telegraf.d/test.conf'
dx 'echo INFLUX_TOKEN=test > /etc/default/telegraf && systemctl restart telegraf && sleep 3 && systemctl is-active telegraf || { journalctl -u telegraf --no-pager | grep -v " I! " | tail -15; false; }'
dx 'grep VmRSS /proc/$(systemctl show -p MainPID --value telegraf)/status'

echo "== replace InfluxData telegraf"
dx 'apt-get purge -y -qq telegraf-light >/dev/null && rm -rf /etc/telegraf'
dx "curl -fsSL https://repos.influxdata.com/influxdata-archive.key | gpg --dearmor > /tmp/influx.gpg
    gpg --show-keys --with-colons /tmp/influx.gpg | grep -q '^fpr:::::::::$INFLUX_KEY_FPR:'
    install -D -m 644 /tmp/influx.gpg /etc/apt/keyrings/influxdata-archive.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' \
        > /etc/apt/sources.list.d/influxdata.list
    apt-get update -qq"
apt_install telegraf
dx 'printf "[agent]\n  interval = \"10s\"\n[[outputs.influxdb_v2]]\n  urls = [\"http://127.0.0.1:8086\"]\n  token = \"\${INFLUX_TOKEN}\"\n" > /etc/telegraf/telegraf.conf
    printf "[[inputs.cpu]]\n" > /etc/telegraf/telegraf.d/test.conf
    echo INFLUX_TOKEN=keep-me > /etc/default/telegraf
    systemctl restart telegraf && sleep 3 && systemctl is-active telegraf && ls -l /usr/bin/telegraf'
# dpkg -i unpacks before removing telegraf, so preinst can save /etc/default/telegraf.
# (apt removes telegraf first and the file is lost: see README.)
dx "dpkg -i /pkgs/telegraf-light_*_arm64.deb >/dev/null"
dx 'dpkg -l telegraf telegraf-light 2>/dev/null | grep -E "^[a-z]{2} "'
dx 'grep -qx INFLUX_TOKEN=keep-me /etc/default/telegraf' || fail "/etc/default/telegraf lost"
dx 'test -f /usr/lib/systemd/system/telegraf.service' || fail "unit lost"
dx 'grep -q outputs.influxdb_v2 /etc/telegraf/telegraf.conf && test -f /etc/telegraf/telegraf.d/test.conf' ||
    fail "config lost"
sleep 3
dx 'systemctl is-active telegraf; systemctl is-enabled telegraf; ls -l /usr/bin/telegraf'

echo "== purge"
dx 'apt-get purge -y -qq telegraf-light >/dev/null'
dx 'ls /etc/default/telegraf /etc/telegraf/telegraf.conf /var/lib/telegraf /usr/bin/telegraf 2>&1 | sed "s/^/  /"'
dx 'test ! -e /etc/systemd/system/multi-user.target.wants/telegraf.service' || fail "unit still enabled"

echo "OK"
