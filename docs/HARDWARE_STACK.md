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
| pesa1234/mt76 `018f6031…` | standalone vendor-oriented mt76 tree | out-of-tree | no | mixing it with upstream mac80211/kernel would break the single-ABI rule | high |
| pesa1234/luci `77dad3f3…` | custom LuCI fork | out-of-tree | no | no hardware control is imported without a 6.12-compatible backend and runtime test | medium/high |
| pesa1234/MT6000_cust_build `c5134874…` | build helper/reference | out-of-tree | no | useful to compare options, but not a patch source for a different release/kernel | medium |
| 2.4 GHz 256-QAM / iBF / EDCCA GUI | pesa1234 trees | vendor/experimental | no | no validated 6.12-compatible implementation or regulatory-safe control plane | medium/high |
| AmneziaWG kernel module | awg-openwrt `98b9eaf2…` | external package source | yes | compiled by this buildroot against its exact kernel ABI | medium |
| Podkop 0.7.22 | itdoginfo/podkop `c0a2736b…` + local compatibility patch | external package source | yes | its dependencies/conflicts are upstream; LuCI registration is adapted for 25.12 | medium |
| full sing-box 1.12.17 | OpenWrt packages feed + local compatibility patch | upstream package | yes | keeps the full upstream variant required by Podkop | medium |

## Решения по pesa1234

Последняя тематическая ветка `next-r4.9.2.rss.mtk` полезна как исторический
источник идей для RSS/MediaTek Wi-Fi, но не как patch feed для OpenWrt 25.12:
она основана на kernel 4.9.2. Никакие её Wi-Fi, hostapd, flow-offload или
Ethernet патчи не переносятся без отдельного минимального diff и стендовых
регрессионных тестов. Это исключает смешивание несовместимых mt76/mac80211,
firmware и kernel ABI.

Классификация результата: часть базового MT7986/mt76 уже есть upstream;
полезных безопасных backport для Linux 6.12 не найдено; RSS/WED/PPE и расширенный
Wi-Fi control относятся к pesa-specific или experimental изменениям; 4.9-based
patches устарели для этой сборки. Поэтому число перенесённых Pesa patch равно
нулю: это документированное решение, а не пропуск обязательной интеграции.

## Podkop и routing

Pinned Makefile Podkop 0.7.22 требует `sing-box`, `curl`, `jq`,
`kmod-nft-tproxy`, `coreutils-base64`, `bind-dig` и объявляет конфликты с
`https-dns-proxy`, `nextdns`, `luci-app-passwall`, `luci-app-passwall2`.
Конфликтующие приложения не включены. Podkop сохраняет штатную схему
firewall4/nftables/TProxy и policy routing; outbound AmneziaWG пользователь
создаёт в LuCI самостоятельно — ключей и фиктивных туннелей в образе нет.

### Patch `0001-luci-25.12-single-buildpackage.patch`

В v0.7.22 после подключения актуального `luci.mk` приложение Podkop
регистрируется дважды: сам `luci.mk` уже вызывает `BuildPackage`, а Makefile
Podkop вызывает его повторно. Это создаёт дублирующийся Kconfig symbol и
рекурсивную зависимость. Патч заменяет второй вызов на комментарий-маркер:
он нужен текстовому scanner OpenWrt, а единственный реальный вызов остаётся в
`luci.mk`. Исходные зависимости Podkop, `sing-box` и перевод
`luci-i18n-podkop-ru` остаются управляемыми upstream `luci.mk`.

### Patch `0001-sing-box-tiny-do-not-provide-full-variant.patch`

В package feed 25.12 `sing-box-tiny` виртуально предоставляет имя `sing-box`,
хотя полный `sing-box` конфликтует с tiny-вариантом. Для пакета Podkop,
выбирающего полный вариант, это превращается в Kconfig-цикл. Патч убирает
только виртуальное предоставление у невыбранного tiny-варианта. В образ
собирается полный `sing-box` 1.12.17 с его стандартным upstream набором
возможностей; tiny-вариант не включается.

## Ограничения проверки

Сборка проверяет состав и ABI-целостность на уровне единого buildroot. Работа
Wi-Fi, 2.5GbE, DFS, WED и реальная селективная маршрутизация требуют теста на
физическом GL-MT6000; для него предусмотрен `scripts/hardware-test.sh`.
