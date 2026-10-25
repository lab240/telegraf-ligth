# telegraf-light

[Telegraf](https://github.com/influxdata/telegraf) с урезанным набором плагинов для устройств NaPi.
Пакет `telegraf-light` в репозитории [repo.napilab.ru](https://repo.napilab.ru).

Официальная сборка содержит все ~300 плагинов. На плате с 512 МБ памяти это много:

| NAPI-C (RK3308, 4×A35, 469 МБ) | telegraf 1.40.2 (InfluxData) | telegraf-light 1.40.2 |
|---|---|---|
| Бинарник | 299 МБ | 22 МБ |
| .deb | 76 МБ | 5,6 МБ |
| RSS (cpu + modbus → influxdb_v2) | ~137 МБ | ~21 МБ |
| `telegraf --test` | 6,0 с | 1,1 с |

## Плагины

Список в [`plugins.txt`](plugins.txt), по одному build tag на строку:

- входы шаблонов датчиков веб-интерфейса NaPi: `cpu`, `modbus`, `snmp`, `mqtt_consumer`;
- метрики устройства: `mem`, `disk`, `diskio`, `net`, `system`, `temp`;
- выход `influxdb_v2`;
- форматы данных для `mqtt_consumer`: `json`, `json_v2`, `influx`, `value`.

Конфиг с плагином не из списка telegraf не загружает
(`undefined but requested input: ...`), napi-api не даст активировать такой датчик.
Нужен ещё плагин: добавить строку в `plugins.txt` (имена как в `plugins/inputs/<name>`
исходников Telegraf), поднять `PKG_REV` в `version.env`, пересобрать.

## Установка из репозитория

```sh
curl -fsSL https://repo.napilab.ru/napilab.gpg | gpg --dearmor > /usr/share/keyrings/napilab.gpg
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/napilab.gpg] https://repo.napilab.ru stable main" \
    > /etc/apt/sources.list.d/napilab.list
apt update && apt install telegraf-light
```

Пакет заменяет `telegraf` (`Provides/Conflicts/Replaces: telegraf`) и сохраняет его пути:
служба `telegraf.service`, пользователь `telegraf`, `/etc/telegraf/telegraf.conf`,
`/etc/telegraf/telegraf.d/`, `/etc/default/telegraf`.

- `/etc/telegraf/telegraf.conf` создаётся при первой установке из
  `/usr/share/telegraf-light/telegraf.conf` (агент 10 с, выход в InfluxDB 2 на
  `127.0.0.1:8086`, org `napi`, bucket `sensors`, токен `${INFLUX_TOKEN}`)
  и дальше не трогается, в том числе при обновлении.
- Токен InfluxDB задаётся в `/etc/default/telegraf`: `INFLUX_TOKEN=...` (файл 640 root:telegraf).
- Пользователь `telegraf` входит в группу `dialout`: Modbus RTU читает последовательные порты.
- Пока нет ни одного входа или токена, telegraf не стартует: это не ошибка установки.
- `purge` удаляет `telegraf.conf`, `/etc/default/telegraf` и `/var/lib/telegraf`.

### Переход с telegraf от InfluxData

`apt install telegraf-light` сначала удаляет `telegraf`, а его postrm удаляет
`/etc/default/telegraf`. Конфиги в `/etc/telegraf` остаются. Токен надо сохранить заранее:

```sh
cp -p /etc/default/telegraf /root/telegraf.default
apt install telegraf-light
cp -p /root/telegraf.default /etc/default/telegraf && systemctl restart telegraf
```

С `dpkg -i telegraf-light_*.deb` файл сохраняется сам: preinst успевает его скопировать.

В штатном `telegraf.conf` от InfluxData включён выход `outputs.influxdb` (v1),
которого в сборке нет. Если конфиг не меняли, замените его на
`/usr/share/telegraf-light/telegraf.conf`.

## Сборка

```sh
./build.sh                 # бинарник → out/arm64/telegraf
./build-deb.sh             # пакет    → out/deb/telegraf-light_<версия>_arm64.deb
./build-deb.sh /tmp/deb arm64 amd64
```

- Версия Telegraf и ревизия пакета в `version.env` (переопределяются
  `TELEGRAF_VERSION`, `PKG_REV`).
- Нужен `go`. Если версия старше той, что в `go.mod` Telegraf, go сам скачивает
  нужный toolchain (`GOTOOLCHAIN=auto`). Без `go` сборка идёт в docker-образе
  `golang:1.27-trixie` (`GO_IMAGE`).
- Сборка кросс-компиляцией без cgo, хост любой: amd64 или arm64.

На repo.napilab.ru пакет собирает и публикует `build-telegraf-light.sh`
из [lab240/repo-napilab](https://github.com/lab240/repo-napilab):
`sudo build-napilab-repo.sh telegraf-light`.

## Проверка

```sh
test/test-install.sh noble      # или trixie
```

В systemd-контейнере (docker, `--privileged`): установка, метрики, отказ на плагин
не из сборки, замена telegraf от InfluxData с сохранением токена, `purge`.

## Лицензия

Telegraf: MIT, InfluxData. Скрипты сборки: MIT.
