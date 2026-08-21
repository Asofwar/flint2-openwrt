# Flint 2 OpenWrt

Воспроизводимая сборка upstream OpenWrt для GL.iNet Flint 2 (GL-MT6000,
MT7986 / Filogic 830): полный LuCI с русской локализацией, WireGuard,
AmneziaWG, Podkop, sing-box, firewall4/nftables и штатный Wi-Fi/Ethernet stack
OpenWrt.

## Зафиксированная база

* OpenWrt: `v25.12.5`, commit `f0a60eee2fe051741c643ea6118718aae1ef17fb`
* kernel: `6.12.94`
* целевое устройство: `glinet_gl-mt6000`, `mediatek/filogic`, `aarch64_cortex-a53`
* AmneziaWG feed: `98b9eaf21f43c1cc54104072f2dce5c9c847f801`; kernel module `1.0.20260611`, LuCI `2.0.4`
* Podkop: `0.7.22`, commit `c0a2736bb95884c19fedf638345ed6148c5fd6af`
* пакетный менеджер выпуска OpenWrt 25.12: APK

Версии и источники собраны в [`scripts/versions.env`](scripts/versions.env).
Анализ MediaTek/mt76/pesa1234 — в [`docs/HARDWARE_STACK.md`](docs/HARDWARE_STACK.md).

## Сборка в Docker

В PowerShell из корня репозитория:

```powershell
docker build --tag flint2-openwrt-builder:25.12.5 .
docker run --rm --user builder --mount "type=bind,src=$((Get-Location).Path),dst=/workspace" flint2-openwrt-builder:25.12.5 ./build.sh
```

Готовые `factory.bin`, `sysupgrade.bin`, manifest и `SHA256SUMS` появятся в
`artifacts/`. Сценарий останавливается при несоответствии source commit или
отсутствии обязательного пакета/образа.

## Прошивка

Используйте только артефакт, в имени которого есть `gl-mt6000`.

* переход с совместимой OpenWrt: LuCI **System → Backup / Flash Firmware** и
  файл `*-sysupgrade.bin`;
* первое восстановление со штатной GL.iNet: используйте только сгенерированный
  `*-factory.bin` и сначала сверяйте SHA256 и актуальную процедуру recovery
  именно для своей ревизии устройства;
* не прошивайте preloader, BL31/U-Boot/FIP: эти файлы не нужны для обычного
  обновления и проект их не меняет.

После загрузки адрес по умолчанию — `http://192.168.1.1/`. Сразу задайте
пароль root и страну Wi-Fi. Создайте обычный WireGuard или AmneziaWG через
**Network → Interfaces → Add new interface**, затем в LuCI Podkop выберите
созданный outbound и добавьте домены/IP/subnet для маршрутизации. Остальной
трафик оставляйте DIRECT.

## Проверка на устройстве

После прошивки с Linux-хоста:

```bash
./scripts/hardware-test.sh root@192.168.1.1
```

Проверяются загрузка `kmod-amneziawg`, временный интерфейс `awg-test`, Wi-Fi,
firewall4 и nftables. Это не заменяет тест пропускной способности, DFS и
клиентской совместимости в вашей радиосреде.

