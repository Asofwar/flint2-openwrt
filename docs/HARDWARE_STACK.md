# Аппаратный стек GL-MT6000

Состояние исследования: 2026-08-21. Основой выбран OpenWrt `v25.12.5` (commit
`f0a60eee2fe051741c643ea6118718aae1ef17fb`), kernel `6.12.94`. В этой версии
цель `glinet_gl-mt6000` официально определена для `mediatek/filogic`; пакетный
формат — APK. Образ использует штатные `factory.bin` и `sysupgrade.bin`, не
заменяет preloader, U-Boot, BL31, таблицу разделов или calibration partitions.

| Feature/Patch | Source | Upstream status | Included | Reason | Risk |
| --- | --- | --- | --- | --- | --- |
| GL-MT6000 DTS/image recipe | OpenWrt v25.12.5 | upstream | yes | exact supported device | low |
| Linux 6.12.94 | OpenWrt v25.12.5 | upstream stable | yes | current stable ABI for this release | low |
| mt76, mac80211, cfg80211 | OpenWrt v25.12.5 | upstream release snapshot | yes, unmodified | driver, mac80211 and kernel remain one tested set | low |
| MT7986/MT7915 firmware | OpenWrt v25.12.5 device packages | upstream | yes | `kmod-mt7986-firmware`, `mt7986-wo-firmware`, `kmod-mt7915e` are device-native | low |
| WED/PPE/RSS | OpenWrt v25.12.5 | upstream | no forced toggle | preserve upstream defaults; acceleration can conflict with policy routing/TProxy | medium |
| pesa1234 `next-r4.9.2.rss.mtk` | pesa1234/openwrt `9d46f811…` | out-of-tree, kernel 4.9 line | reference only | not ABI-compatible with Linux 6.12 and unsuitable as a broad backport | high |
| 2.4 GHz 256-QAM / iBF / EDCCA GUI | pesa1234 trees | vendor/experimental | no | no validated 6.12-compatible implementation or regulatory-safe control plane | medium/high |
| AmneziaWG kernel module | awg-openwrt `98b9eaf2…` | external package source | yes | compiled by this buildroot against its exact kernel ABI | medium |
| Podkop 0.7.22 | itdoginfo/podkop `c0a2736b…` | external package source | yes | its upstream Makefile controls dependencies and conflicts | medium |

## Решения по pesa1234

Последняя тематическая ветка `next-r4.9.2.rss.mtk` полезна как исторический
источник идей для RSS/MediaTek Wi-Fi, но не как patch feed для OpenWrt 25.12:
она основана на kernel 4.9.2. Никакие её Wi-Fi, hostapd, flow-offload или
Ethernet патчи не переносятся без отдельного минимального diff и стендовых
регрессионных тестов. Это исключает смешивание несовместимых mt76/mac80211,
firmware и kernel ABI.

## Podkop и routing

Pinned Makefile Podkop 0.7.22 требует `sing-box`, `curl`, `jq`,
`kmod-nft-tproxy`, `coreutils-base64`, `bind-dig` и объявляет конфликты с
`https-dns-proxy`, `nextdns`, `luci-app-passwall`, `luci-app-passwall2`.
Конфликтующие приложения не включены. Podkop сохраняет штатную схему
firewall4/nftables/TProxy и policy routing; outbound AmneziaWG пользователь
создаёт в LuCI самостоятельно — ключей и фиктивных туннелей в образе нет.

## Ограничения проверки

Сборка проверяет состав и ABI-целостность на уровне единого buildroot. Работа
Wi-Fi, 2.5GbE, DFS, WED и реальная селективная маршрутизация требуют теста на
физическом GL-MT6000; для него предусмотрен `scripts/hardware-test.sh`.

