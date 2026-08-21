# Flint 2 Custom OpenWrt

Воспроизводимая сборка стабильного upstream OpenWrt для GL.iNet Flint 2
(GL-MT6000, MT7986 / Filogic 830). Образ сохраняет штатный GL.iNet bootloader
и OEM recovery, не содержит учётных данных и рассчитан на домашний роутер:
полный LuCI на русском языке, WireGuard, AmneziaWG, Podkop, full sing-box,
firewall4/nftables, IPv6, PPPoE и штатный Wi-Fi/Ethernet стек OpenWrt.

## Hardware

| Поле | Значение |
| --- | --- |
| устройство | `glinet_gl-mt6000` |
| target/subtarget | `mediatek/filogic` |
| архитектура | `aarch64_cortex-a53` |
| SoC | MediaTek MT7986 / Filogic 830 |

Это не GL.iNet SDK и не штатная прошивка GL.iNet с заменённым UI. Базой служит
официальный device recipe OpenWrt, поэтому используются только её
`factory.bin` и `sysupgrade.bin` для GL-MT6000.

## Versions

| Компонент | Зафиксированная версия |
| --- | --- |
| OpenWrt | `v25.12.5`, `f0a60eee2fe051741c643ea6118718aae1ef17fb` |
| kernel | `6.12.94` |
| AmneziaWG feed | `98b9eaf21f43c1cc54104072f2dce5c9c847f801` |
| Podkop | `0.7.22`, `c0a2736bb95884c19fedf638345ed6148c5fd6af` |
| sing-box | upstream package `1.12.17` |

Полный список immutable revisions — в [`scripts/versions.env`](scripts/versions.env).

## Differences from vanilla OpenWrt

В образ добавлены LuCI, HTTPS, русский язык, `dnsmasq-full`, PPPoE, DSA/VLAN,
IPv6, WPA2/WPA3, WireGuard, AmneziaWG 2.x, Podkop и его LuCI, full `sing-box`,
`kmod-nft-tproxy`, диагностика и QoS/SQM. Конфликтующие с Podkop пакеты
`https-dns-proxy`, `nextdns`, Passwall и Passwall2 не включены.

## Pesa1234 patches and Wi-Fi stack

`pesa1234/openwrt` и связанные mt76/LuCI деревья были исследованы. Их
релевантная ветка основана на kernel 4.9 и не совместима с OpenWrt 25.12 /
kernel 6.12. Поэтому Wi-Fi, mac80211, firmware, Ethernet и kernel ABI берутся
из одного upstream tree; непроверенные WED/PPE/RSS/256-QAM/iBF/EDCCA изменения
не переносятся. Это сознательный выбор стабильности и корректной policy
routing. Обоснование и оба минимальных compatibility patch — в
[`docs/HARDWARE_STACK.md`](docs/HARDWARE_STACK.md).

Аппаратный offload не включается принудительно. При Podkop/TProxy/VPN policy
routing он может обходить правила. Сначала проверьте selective routing, затем
при необходимости тестируйте software/hardware flow offload отдельно; при
ошибках отключите offload и очистите conntrack.

## Build locally

### Windows + Docker Desktop

В PowerShell из корня репозитория:

```powershell
.\build-docker.ps1
```

Исходники OpenWrt и кэш находятся в named Docker volume, а не в OneDrive/NTFS.
Для другого числа потоков: `.\build-docker.ps1 -Jobs 12`.

### Linux

Поддерживаемая воспроизводимая среда — Dockerfile проекта:

```bash
docker build --tag flint2-openwrt-builder:25.12.5 .
docker run --rm --user builder \
  --mount type=bind,src="$PWD",dst=/workspace \
  flint2-openwrt-builder:25.12.5 ./build.sh
```

`build.sh` фиксирует OpenWrt и feeds, применяет строго два compatibility patch,
вызывает `make defconfig`, загружает исходники, собирает image и выполняет
проверку. Он прекращает работу при несовпадении pin или непригодности patch.

## GitHub Actions

Workflow хранится в репозитории и умеет `workflow_dispatch`, push и pull
request, однако в GitHub он сейчас вручную отключён по решению владельца
репозитория. Локальная сборка остаётся основной проверкой до фактической
прошивки.

## Firmware artifacts

После сборки каталог `artifacts/` содержит:

* `*-sysupgrade.bin` — обновление с совместимого OpenWrt;
* `*-factory.bin` — первоначальная установка через совместимый U-Boot recovery;
* `packages.manifest` и `openwrt-sha256sums` из upstream;
* `config.buildinfo`, `feeds.buildinfo`, `version.buildinfo`, `BUILD_INFO.txt`;
* `SHA256SUMS` для всех собранных артефактов.

`BUILD_INFO.txt` содержит неизменяемые commit OpenWrt, AWG, Podkop и pesa, а
также фактические версии mt76/mac80211, MT7986 firmware и sing-box из манифеста
собранного образа.

Проверка перед прошивкой:

```bash
cd artifacts
sha256sum -c SHA256SUMS
```

Используйте только файл, в имени которого есть `gl-mt6000`.

## Flash from GL.iNet firmware and OpenWrt upgrade

С сохранённого upstream OpenWrt используйте LuCI **System → Backup / Flash
Firmware** и `*-sysupgrade.bin`. При первом переходе с GL.iNet используйте
только соответствующий `*-factory.bin` из этой сборки и не сохраняйте старые
конфигурации GL.iNet.

Перед прошивкой сохраните backup UCI. Не прошивайте вручную preloader, U-Boot,
BL31, FIP, таблицу разделов или factory/calibration partitions: проект их не
меняет и они не нужны для обычного обновления.

## First boot, LuCI and Russian language

После старта подключитесь к LAN и откройте `http://192.168.1.1/`. Немедленно
задайте пароль root, выберите страну Wi-Fi и убедитесь, что в LuCI доступен
русский язык. Для HTTPS используйте LuCI после установки пароля; пакет
`luci-ssl-openssl` встроен.

## Configure Wi-Fi, PPPoE, VLAN and IPv6

* Wi-Fi: **Network → Wireless**. Выберите свою страну, WPA2/WPA3-SAE и не
  форсируйте 160 MHz или DFS-канал до проверки клиентов.
* PPPoE: **Network → Interfaces → Add new interface → PPPoE**. Логин и пароль
  вводятся только в LuCI и не должны попадать в Git.
* VLAN/DSA: создавайте bridge VLAN filtering, tagged/untagged ports и PVID в
  **Network → Devices**. Это DSA, не старый swconfig.
* IPv6: не удалён; стандартные RA/DHCPv6 настраиваются в **Network →
  Interfaces** и **Network → DHCP and DNS**.

## Configure WireGuard and AmneziaWG

Оба протокола доступны в **Network → Interfaces → Add new interface**.

* Для WireGuard выберите **WireGuard VPN**.
* Для AmneziaWG выберите **AmneziaWG** и заполните ключи, endpoint, peer и
  параметры AWG 2.x в LuCI.

`kmod-amneziawg` собран в том же buildroot с kernel `6.12.94`; готовые сторонние
APK, `--force-depends` и ручная подмена vermagic не используются. Приватные
ключи не хранятся в репозитории.

## Configure Podkop and split routing through AmneziaWG

В LuCI Podkop пользователь может включить сервис, выбрать outbound/interface,
добавить домены, IP и subnet lists и перезапустить сервис. Базовый сценарий:

1. Проверьте свой публичный IP при DIRECT-подключении.
2. Создайте и поднимите AmneziaWG interface в LuCI.
3. Проверьте, что туннель действительно работает отдельно от Podkop.
4. В Podkop выберите этот interface как outbound и добавьте тестовый домен.
5. Убедитесь, что он идёт через туннель, а иной ресурс остаётся DIRECT.
6. Проверьте DNS leak и повторите тест после reboot.

Не создавайте фиктивный VPN interface: ключи и endpoint вводит владелец
роутера. Podkop использует штатные firewall4/nftables/TProxy/sing-box rules.

## Diagnostics and performance testing

После добавления host key роутера выполните с доверенного Linux-хоста:

```bash
./scripts/hardware-test.sh root@192.168.1.1
```

Скрипт проверяет package presence, `modprobe amneziawg`, временный интерфейс
AWG, LuCI menu/переводы, Podkop, sing-box, nftables, firewall4, Wi-Fi и
interrupt diagnostics. Он не изменяет VPN-конфигурацию.

На самом роутере доступна команда:

```sh
flint2-info
```

Она выводит версию OpenWrt и kernel, фактические версии mt76, Wi-Fi firmware,
mac80211, wpad, AmneziaWG, Podkop и sing-box, а также наблюдаемые состояния
WED/PPE и UCI-настроек software/hardware flow offload. Отсутствие загруженного
модуля не является доказательством выключенной встроенной функции, поэтому
состояние WED/PPE всё равно подтверждайте на реальном устройстве.

Для производительности измеряйте отдельно `iperf3` LAN→LAN, Wi-Fi→LAN и 2.5GbE
в одном режиме за раз. Для проверки WED/offload, DFS, EEE/autonegotiation и
2.5GbE link flap необходим физический GL-MT6000 и реальная сеть.

## Backup and recovery

LuCI backup сохраняет UCI конфигурации (`network`, `wireless`, `firewall`,
`dhcp`, `podkop`, AmneziaWG). Перед sysupgrade создайте архив и не ожидайте,
что сторонние APK после перехода между релизами будут сохранены автоматически.

Если LuCI или DHCP недоступны, подключитесь Ethernet-кабелем и используйте
штатный U-Boot Web Recovery GL.iNet:

1. Выключите роутер и подключите ПК только к **LAN 2, LAN 3 или LAN 4**;
   LAN 1 для GL-MT6000 использовать нельзя.
2. Удерживайте Reset и включите питание. Для Flint 2 отпустите кнопку после
   шести синих миганий, когда LED станет белым и постоянным.
3. Назначьте ПК `192.168.1.2/24`, откройте `http://192.168.1.1` и загрузите
   подходящий U-Boot-compatible firmware.
4. Для возврата к GL.iNet скачайте официальную прошивку именно GL-MT6000 и
   используйте тот же recovery UI; после успешной загрузки верните IP ПК в
   DHCP.

Официальная инструкция GL.iNet: [U-Boot recovery](https://docs.gl-inet.com/router/en/4/faq/debrick/).
Recovery стирает настройки и установленные пакеты. Никогда не используйте
консольные erase/write команды для bootloader или calibration data.

## Updating to a newer OpenWrt and known issues

Все источники централизованы в `scripts/versions.env`. При обновлении pin
обязательно заново проверьте device symbol, kernel, feeds, применимость двух
patch, full `sing-box`, `kmod-amneziawg` ABI, Podkop/LuCI и результат
`./scripts/verify-build.sh`.

Статическая проверка и успешная сборка не заменяют реальные тесты Wi-Fi,
2.5GbE, DFS, WED, PPPoE или selective routing на конкретном роутере. Не
считайте эти runtime-сценарии подтверждёнными до выполнения hardware-test и
сетевого чек-листа выше.
