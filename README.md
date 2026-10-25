# telegraf-light

[Telegraf](https://github.com/influxdata/telegraf) with a reduced plugin set for NaPi devices.
Package `telegraf-light` in [repo.napilab.ru](https://repo.napilab.ru).
Русская версия: [README-RU.md](README-RU.md).

| NAPI-C (RK3308, 4×A35, 469 MB) | telegraf 1.40.2 (InfluxData) | telegraf-light 1.40.2 |
|---|---|---|
| Binary | 299 MB | 22 MB |
| .deb | 76 MB | 5.6 MB |
| RSS (cpu + modbus → influxdb_v2) | ~137 MB | ~21 MB |
| `telegraf --test` | 6.0 s | 1.1 s |

## Plugins

[`plugins.txt`](plugins.txt), one build tag per line: inputs `cpu`, `modbus`, `snmp`,
`mqtt_consumer` (NaPi web UI sensor templates), `mem`, `disk`, `diskio`, `net`, `system`,
`temp`; output `influxdb_v2`; parsers `json`, `json_v2`, `influx`, `value`.
Telegraf refuses a config with any other plugin. To add one, add a line,
bump `PKG_REV` in `version.env` and rebuild.

## Install

```sh
curl -fsSL https://repo.napilab.ru/napilab.gpg | gpg --dearmor > /usr/share/keyrings/napilab.gpg
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/napilab.gpg] https://repo.napilab.ru stable main" \
    > /etc/apt/sources.list.d/napilab.list
apt update && apt install telegraf-light
```

Replaces the `telegraf` package and keeps its paths: `telegraf.service`, user `telegraf`
(also in `dialout` for Modbus RTU), `/etc/telegraf/telegraf.conf` (created once from
`/usr/share/telegraf-light/telegraf.conf`), `/etc/telegraf/telegraf.d/`,
`/etc/default/telegraf` (`INFLUX_TOKEN=...`).

Coming from InfluxData's telegraf: `apt` removes it first and its postrm deletes
`/etc/default/telegraf`; back it up before `apt install telegraf-light`
(`dpkg -i` keeps it). Its default `telegraf.conf` uses `outputs.influxdb` (v1),
which is not in this build.

## Build

```sh
./build.sh                 # → out/arm64/telegraf
./build-deb.sh             # → out/deb/telegraf-light_<version>_arm64.deb
./build-deb.sh /tmp/deb arm64 amd64
test/test-install.sh noble # systemd container test (or trixie)
```

Needs `go` (older go fetches the toolchain from Telegraf's `go.mod`) or docker
(`golang:1.27-trixie`). Versions in `version.env`. On repo.napilab.ru:
`sudo build-napilab-repo.sh telegraf-light` ([lab240/repo-napilab](https://github.com/lab240/repo-napilab)).

## License

Telegraf: MIT, InfluxData. Build scripts: MIT.
