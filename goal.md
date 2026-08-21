Ты работаешь как senior OpenWrt/Linux/embedded/network engineer.



Твоя задача — создать, собрать и проверить полноценную кастомную прошивку для:



\* GL.iNet Flint 2

\* GL-MT6000

\* MediaTek MT7986 / Filogic 830

\* target: `mediatek`

\* subtarget: `filogic`

\* architecture: `aarch64\_cortex-a53`

\* device: `glinet\_gl-mt6000`



Это должна быть не минимальная прошивка для разработчика, а полноценная стабильная прошивка домашнего роутера для обычного пользователя.



Основные требования:



```text

Upstream OpenWrt stable

\+

актуальный и исправленный hardware stack MT7986

\+

актуальный mt76 / Wi-Fi firmware

\+

проверенные улучшения для Flint 2 из проектов pesa1234

\+

полный LuCI GUI

\+

русский интерфейс

\+

AmneziaWG 2.0

\+

AmneziaWG LuCI

\+

Podkop

\+

Podkop LuCI

\+

sing-box

\+

WireGuard

\+

firewall4 / nftables

\+

все необходимые функции обычного домашнего роутера

```



Главный принцип:



```text

Stability

>

Correct routing

>

Podkop compatibility

>

Wi-Fi stability

>

Ethernet stability

>

Latency

>

Maximum benchmark throughput

```



Не жертвуй стабильностью ради нескольких процентов производительности.



\---



\# 1. СНАЧАЛА ПРОВЕДИ ИССЛЕДОВАНИЕ



Не начинай с бездумного редактирования `.config`.



Сначала проверь актуальное состояние следующих проектов на момент выполнения задачи:



```text

https://github.com/openwrt/openwrt

https://github.com/openwrt/mt76



https://github.com/amnezia-vpn/

https://github.com/Slava-Shchipunov/awg-openwrt



https://github.com/itdoginfo/podkop



https://github.com/pesa1234/openwrt

https://github.com/pesa1234/mt76

https://github.com/pesa1234/luci

https://github.com/pesa1234/MT6000\_cust\_build

```



Определи:



1\. последнюю стабильную OpenWrt, официально поддерживающую GL-MT6000;

2\. актуальный kernel;

3\. актуальную ветку `mediatek/filogic`;

4\. актуальный `mt76`;

5\. актуальный Wi-Fi firmware MT7986;

6\. актуальную версию AmneziaWG 2.x;

7\. актуальную версию Podkop;

8\. требования Podkop к sing-box;

9\. текущую package system OpenWrt — APK или OPKG;

10\. последнюю актуальную ветку pesa1234 именно для GL-MT6000;

11\. какие исправления pesa1234 уже попали upstream;

12\. какие его исправления всё ещё полезны;

13\. какие его патчи уже устарели или конфликтуют с выбранной OpenWrt.



Не считать версии из этого ТЗ абсолютной истиной.



Если появилась более новая стабильная OpenWrt, используй её при условии совместимости со всеми компонентами.



На момент написания ТЗ ориентиром является семейство OpenWrt 25.12.x.



\---



\# 2. БАЗА — UPSTREAM OPENWRT



Основой должен оставаться:



```text

openwrt/openwrt

```



Не использовать GL.iNet SDK как базу.



Не превращать сборку в модифицированную штатную прошивку GL.iNet.



Мне нужен полноценный upstream OpenWrt, оптимизированный именно под GL-MT6000.



Не добавлять proprietary GL.iNet Web UI.



Загрузчик GL.iNet должен оставаться штатным.



Не менять без критической необходимости:



```text

preloader

U-Boot

BL31

partition table

factory/calibration partitions

```



\---



\# 3. REPRODUCIBLE BUILD



Создай полностью воспроизводимый проект.



Структура примерно:



```text

.

├── README.md

├── build.sh

├── clean.sh

├── Makefile

├── configs/

│   └── gl-mt6000.config

├── patches/

│   ├── openwrt/

│   ├── mt76/

│   └── mediatek/

├── packages/

├── files/

├── scripts/

│   ├── verify-build.sh

│   ├── hardware-test.sh

│   ├── collect-artifacts.sh

│   └── flint2-info.sh

├── docs/

│   └── HARDWARE\_STACK.md

└── .github/

&#x20;   └── workflows/

&#x20;       └── build.yml

```



Можно изменить структуру, если есть технически более правильный вариант.



Все версии должны быть pin'нуты:



```text

OpenWrt commit/tag

mt76 commit

AmneziaWG commit/tag

Podkop commit/tag

sing-box version/source

дополнительные patch sources

```



Не использовать плавающий `master/main`, если можно зафиксировать конкретный commit.



\---



\# 4. ЦЕЛЕВОЕ УСТРОЙСТВО



Проверь реальные Kconfig symbols выбранного релиза.



Ожидается примерно:



```text

CONFIG\_TARGET\_mediatek=y

CONFIG\_TARGET\_mediatek\_filogic=y

CONFIG\_TARGET\_mediatek\_filogic\_DEVICE\_glinet\_gl-mt6000=y

```



Не использовать generic image.



Итоговый sysupgrade должен быть предназначен строго для GL-MT6000.



\---



\# 5. AMNEZIAWG 2.0



Обязательно встроить AmneziaWG непосредственно в firmware.



Нужен именно kernel implementation.



Ожидаемые пакеты:



```text

kmod-amneziawg

amneziawg-tools

luci-proto-amneziawg

luci-i18n-amneziawg-ru

```



Но сначала проверь актуальные названия.



Критически важно:



```text

kmod-amneziawg

```



должен быть скомпилирован против ТОГО ЖЕ:



```text

kernel

kernel config

OpenWrt tree

ABI

```



что используется основной прошивкой.



Запрещено просто скачать случайный готовый `.apk/.ipk` AmneziaWG и принудительно установить его.



Запрещено:



```text

\--force-depends

\--force-depends-version

ручная подмена vermagic

подмена kernel version

игнорирование ABI mismatch

```



Правильная схема:



```text

OpenWrt source

\+

AmneziaWG package sources

&#x20;      ↓

единая сборка

&#x20;      ↓

kernel + kmod-amneziawg

```



После загрузки должно работать:



```bash

modprobe amneziawg



lsmod | grep -i amnezia



awg --version

```



и тест:



```bash

ip link add awg-test type amneziawg

ip link show awg-test

ip link del awg-test

```



Адаптируй команды к актуальному API AmneziaWG.



\---



\# 6. AMNEZIAWG GUI



Нельзя считать AmneziaWG готовым, если его можно настраивать только через SSH.



В:



```text

Network → Interfaces → Add new interface

```



должен присутствовать:



```text

AmneziaWG

```



Все необходимые параметры AWG 2.x должны редактироваться через LuCI.



Private key не должен попадать в Git.



\---



\# 7. ОБЫЧНЫЙ WIREGUARD



Кроме AmneziaWG оставить поддержку обычного WireGuard.



Добавить при совместимости:



```text

kmod-wireguard

wireguard-tools

luci-proto-wireguard

```



В GUI пользователь должен иметь выбор:



```text

WireGuard

AmneziaWG

```



\---



\# 8. PODKOP



Обязательно встроить:



```text

podkop

luci-app-podkop

luci-i18n-podkop-ru

```



Источник:



```text

https://github.com/itdoginfo/podkop

```



Проверь актуальный:



```text

podkop/Makefile

```



и автоматически учти реальные dependencies.



Ожидаются как минимум:



```text

sing-box

curl

jq

kmod-nft-tproxy

coreutils-base64

bind-dig

```



Но Makefile upstream является источником истины.



\---



\# 9. PODKOP GUI



Podkop должен полностью управляться через LuCI.



Пользователь должен иметь возможность без SSH:



\* включить/выключить Podkop;

\* выбрать режим;

\* настроить routing;

\* задать domain lists;

\* задать IP/subnet lists;

\* выбрать outbound;

\* настроить proxy;

\* посмотреть состояние;

\* посмотреть диагностику;

\* перезапустить сервис.



Проверь актуальную работу Dashboard.



Если есть известные проблемы Dashboard + HTTPS, выясни актуальное состояние upstream и реализуй лучший поддерживаемый вариант.



Не отключать глобально HTTPS ради Podkop.



\---



\# 10. PODKOP + AMNEZIAWG



Один из основных сценариев:



```text

Internet

&#x20;  │

&#x20;Podkop

&#x20;↙   ↘

Direct  AmneziaWG

```



Пользователь должен иметь возможность направлять:



```text

определённые домены

определённые IP

определённые subnet

```



через AmneziaWG, а остальной трафик оставлять DIRECT.



Не создавай фиктивный VPN configuration.



Пользователь сам добавит ключи и endpoint.



Podkop должен корректно работать с AmneziaWG routing.



Если механизм основан на:



```text

nftables

policy routing

TProxy

sing-box

```



используй штатную архитектуру Podkop.



\---



\# 11. КОНФЛИКТЫ PODKOP



Проверь актуальный `CONFLICTS` в Makefile.



Не включать конфликтующие компоненты без необходимости.



В частности проверить:



```text

https-dns-proxy

luci-app-https-dns-proxy

nextdns

passwall

passwall2

luci-app-passwall

luci-app-passwall2

```



Не устанавливать их просто ради количества функций.



\---



\# 12. LUCI — КРИТИЧЕСКОЕ ТРЕБОВАНИЕ



Прошивка предназначена обычному пользователю.



Обязательно включить полноценный LuCI.



Ожидаются:



```text

luci

luci-ssl

uhttpd

rpcd

```



и необходимые зависимости.



Через GUI должны быть доступны:



```text

Status

Overview



Network

Interfaces

Wi-Fi

DHCP/DNS

Routes

Firewall

VLAN



VPN

WireGuard

AmneziaWG



Podkop



System

Administration

Startup

Software

Backup

Flash firmware

Reboot

Logs



Diagnostics

```



\---



\# 13. РУССКИЙ GUI



Добавить русскую локализацию LuCI.



Включить доступные:



```text

luci-i18n-base-ru

luci-i18n-podkop-ru

luci-i18n-amneziawg-ru

```



и остальные необходимые translation packages.



Если названия изменились — использовать актуальные.



\---



\# 14. FLINT 2 ADVANCED GUI



Изучи расширения LuCI:



```text

pesa1234/luci

```



и перенеси полезные настройки hardware acceleration / Wi-Fi, если они совместимы и лицензия разрешает.



Желательно создать раздел вроде:



```text

System → Flint 2 Advanced

```



или:



```text

Network → Hardware Acceleration

```



Где показывать только реально работающие функции.



Возможные параметры:



```text

WED

Software Flow Offload

Hardware Flow Offload

RSS status

ATF

HW-ATF

iBF

EDCCA

256-QAM / VHT 2.4

```



Нельзя делать декоративные переключатели.



Каждый переключатель должен реально менять соответствующую настройку.



\---



\# 15. ИССЛЕДОВАТЬ PESA1234



Особое внимание:



```text

https://github.com/pesa1234

```



Исследовать последние актуальные ветки его OpenWrt для MT6000.



В прошлом использовались ветки наподобие:



```text

next-r4.x.x.rss.mtk

```



Но обязательно найди актуальную ветку сам.



Проведи diff с:



```text

OpenWrt stable

OpenWrt main

pesa1234 OpenWrt

pesa1234 mt76

```



Раздели изменения на:



```text

Already upstream

Useful backport

Pesa-specific useful

Experimental

Obsolete

Not relevant

```



\---



\# 16. HARDWARE\_STACK.md



Создай:



```text

docs/HARDWARE\_STACK.md

```



В нём таблица:



| Feature/Patch | Source | Upstream status | Included | Reason | Risk |

| ------------- | ------ | --------------- | -------- | ------ | ---- |



Зафиксируй все сторонние изменения.



\---



\# 17. MT76



Проведи отдельный анализ:



```text

OpenWrt stable mt76

OpenWrt main mt76

pesa1234 mt76

```



Выбери наиболее новый, стабильный и совместимый вариант.



Не брать автоматически самый новый HEAD.



Проверить совместимость:



```text

kernel

mac80211

cfg80211

hostapd

firmware

```



Особенно искать исправления:



```text

MT7986

MT7975

mt7915

GL-MT6000

Flint 2



Wi-Fi disconnect

2.4 GHz slowdown

5 GHz slowdown

ping spikes

160 MHz

DFS

WED

beamforming

OFDMA

MU-MIMO

```



\---



\# 18. WIFI FIRMWARE



Использовать актуальный совместимый firmware для:



```text

MT7986

MT7975

```



Проверить:



```text

WM firmware

WA firmware

ROM patch

```



и остальные необходимые blobs.



Не смешивать driver и firmware разных несовместимых поколений.



\---



\# 19. MAC80211 / CFG80211



Проверить актуальные:



```text

mac80211

cfg80211

wireless-regdb

```



и backports.



Особое внимание:



```text

HE

HE160

DFS

CAC

radar detection

beamforming

MU-MIMO

OFDMA

power save

roaming

client compatibility

```



\---



\# 20. WPAD / HOSTAPD



Не использовать слишком урезанный Wi-Fi stack.



Поддержать:



```text

WPA2

WPA3

SAE

PMF

OWE



802.11k

802.11v

802.11r

```



если это возможно без конфликтов.



Настройки должны быть доступны через LuCI.



\---



\# 21. WI-FI 2.4 GHZ



Полностью поддержать штатный Wi-Fi 6 2.4 GHz.



Исследовать улучшения pesa1234:



```text

256-QAM / VHT on 2.4 GHz

```



Если:



\* действительно улучшает работу;

\* стабильно;

\* не нарушает regulatory domain;

\* не ломает IoT-клиентов;



сделать доступной опцией.



По умолчанию использовать безопасную совместимую конфигурацию.



\---



\# 22. WI-FI 5 GHZ



Поддержать:



```text

20 MHz

40 MHz

80 MHz

160 MHz

```



где это разрешено regulatory domain.



Не форсировать 160 MHz.



Исправно должен работать DFS.



\---



\# 23. BEAMFORMING



Исследовать:



```text

SU Beamforming

MU Beamforming

iBF

eBF

```



Включить только реально поддерживаемые MT7986 hardware/firmware функции.



Если pesa1234 добавляет рабочее управление iBF — адаптировать его.



\---



\# 24. ATF / HW-ATF



Исследовать:



```text

Airtime Fairness

ATF

HW-ATF

```



Если актуальный stack это поддерживает — добавить управление через GUI.



По возможности:



```text

Auto

Software

Hardware

Disabled

```



Но только если такие реальные режимы существуют.



\---



\# 25. EDCCA



Исследовать:



```text

EDCCA

```



в MT7986 и pesa1234.



Добавить расширенное управление только если оно реально поддерживается.



Не нарушать regulatory requirements.



\---



\# 26. REGULATORY



Ничего не запрещено для «усиления Wi-Fi»





Под улучшением Wi-Fi имеется в виду:



```text

актуальные драйверы

актуальный firmware

beamforming

OFDMA

MU-MIMO

160 MHz

RSS

WED

ATF

оптимизация CPU/IRQ

исправления mt76

```



\---



\# 27. RSS



Исследовать:



```text

Receive Side Scaling

RSS

```



для MT7986.



Проверить:



```text

RSS

RPS

XPS

IRQ affinity

NAPI

packet steering

```



Не использовать hardcoded CPU masks без анализа.



Проверить работу:



```bash

cat /proc/interrupts

cat /proc/softirqs

```



\---



\# 28. WED



Исследовать и поддержать:



```text

MediaTek Wireless Ethernet Dispatch

WED

```



При стабильной работе добавить.



Не включать намертво.



Через GUI пользователь должен иметь возможность:



```text

Auto

Enabled

Disabled

```



если реализация позволяет.



Также добавить runtime status.



\---



\# 29. MEDIAtek PPE / FLOW OFFLOAD



Поддержать актуальную MediaTek PPE.



В LuCI должны быть:



```text

Software Flow Offloading

Hardware Flow Offloading

```



если они доступны.



Но обязательно проверить взаимодействие с:



```text

Podkop

TProxy

nftables

sing-box

WireGuard

AmneziaWG

SQM

```



\---



\# 30. PODKOP ВАЖНЕЕ HARDWARE FLOW OFFLOAD



Если HFO обходится вокруг правил Podkop/TProxy или ломает selective routing:



```text

HFO default = OFF

```



или выбрать другой безопасный режим.



Не включать hardware acceleration только ради красивого Speedtest.



В GUI добавить предупреждение:



```text

Hardware Flow Offload может конфликтовать

с Podkop/TProxy/VPN policy routing.

```



\---



\# 31. ETHERNET



Полностью поддержать Ethernet Flint 2.



Проверить актуальные исправления для:



```text

RTL8221B

MT7531

mtk\_eth\_soc

DSA

PPE

```



Особенно:



```text

2.5GbE

autonegotiation

EEE

link up/down

DHCP после boot

link flapping

```



Поддержать:



```text

100 Mbps

1 Gbps

2.5 Gbps

```



\---



\# 32. VLAN / DSA



Через LuCI должны нормально работать:



```text

bridges

VLAN filtering

tagged

untagged

PVID

DSA

```



Не использовать старую swconfig архитектуру.



\---



\# 33. PPPoE



Добавить полноценную поддержку PPPoE.



Ожидаются:



```text

ppp

ppp-mod-pppoe

luci-proto-ppp

```



Если актуальные названия отличаются — использовать правильные.



PPPoE должен настраиваться через LuCI.



\---



\# 34. IPV6



Не удалять IPv6 ради уменьшения image.



Поддержать стандартный OpenWrt IPv6 stack:



```text

DHCPv6

RA

IPv6 WAN

IPv6 LAN

firewall

```



\---



\# 35. FIREWALL



Использовать только современную архитектуру:



```text

firewall4

nftables

```



Не тащить legacy iptables без необходимости.



\---



\# 36. DNS



Не заменять стандартный DNS resolver OpenWrt без необходимости.



Не устанавливать автоматически:



```text

AdGuard Home

NextDNS

https-dns-proxy

```



если это конфликтует или не требуется.



DNS должен корректно работать вместе с Podkop.



\---



\# 37. ПОЛЕЗНЫЕ ПАКЕТЫ



Добавить нормальный набор для домашнего роутера:



```text

curl

wget-ssl

ca-bundle

ca-certificates



nano

htop



tcpdump

ethtool



jq

bind-dig



ip-full

iperf3

```



Можно добавить:



```text

bash

rsync

```



если overhead разумный.



Не добавлять:



```text

Docker

Kubernetes

gcc

clang

python

node.js

development headers

torrent clients

```



без отдельной необходимости.



\---



\# 38. IPERF3



Добавить `iperf3`.



Но НЕ запускать iperf server автоматически.



\---



\# 39. USB



Сохранить нормальную поддержку USB Flint 2.



Нужно работать:



```text

USB storage

USB 3.x

USB network adapters

```



Добавить разумные filesystem packages только если они действительно нужны обычному пользователю.



\---



\# 40. TEMPERATURE



Не отключать thermal protection.



По возможности отображать температуру:



```text

Status → Overview

```



или отдельной страницей Flint 2.



\---



\# 41. НОРМАЛЬНЫЕ DEFAULTS



После чистой прошивки:



```text

LAN работает

DHCP работает

DNS работает

firewall работает

LuCI работает

SSH работает

```



Не открывать:



```text

22

80

443

```



на WAN.



Не включать UPnP автоматически.



Не прошивать:



```text

SSID

Wi-Fi password

country

VPN key

API tokens

SSH private keys

```



Пользователь задаёт их самостоятельно.



\---



\# 42. SOFTWARE MANAGEMENT



В GUI должна работать страница управления пакетами.



Если выбранная OpenWrt использует APK — документацию писать под APK.



Не писать только команды OPKG по старой памяти.



\---



\# 43. BACKUP / SYSUPGRADE



Через LuCI должно работать:



```text

System → Backup / Flash Firmware

```



Проверь сохранение UCI configuration для:



```text

network

wireless

firewall

dhcp

podkop

AmneziaWG

```



В README объясни ограничения сохранения сторонних пакетов после перехода на обычный upstream OpenWrt.



\---



\# 44. FLASHING



Очень внимательно изучи процедуру именно GL.iNet Flint 2 GL-MT6000.



Для штатного перехода на OpenWrt использовать правильный образ, предназначенный для этой процедуры.



Не советовать пользователю прошивать:



```text

preloader

U-Boot

BL31

factory partitions

```



без критической необходимости.



Сохранять OEM recovery.



\---



\# 45. RECOVERY



README должен содержать:



```text

Recovery

```



с описанием:



1\. входа в GL-MT6000 U-Boot Web Recovery;

2\. восстановления официальной GL.iNet firmware;

3\. восстановления через Ethernet;

4\. действий при недоступном LuCI;

5\. действий при отсутствии DHCP;

6\. что нельзя трогать в bootloader.



\---



\# 46. BUILD.SH



Создай:



```text

build.sh

```



который с чистой Linux среды:



1\. устанавливает/проверяет build dependencies;

2\. клонирует нужные source trees;

3\. checkout фиксированных commits;

4\. подключает feeds;

5\. интегрирует AmneziaWG;

6\. интегрирует Podkop;

7\. применяет проверенные MT7986 patches;

8\. генерирует `.config`;

9\. выполняет `make defconfig`;

10\. скачивает sources;

11\. собирает toolchain;

12\. собирает packages;

13\. собирает image;

14\. выполняет verification;

15\. складывает результаты в `artifacts/`.



\---



\# 47. GITHUB ACTIONS



Обязательно:



```text

.github/workflows/build.yml

```



Поддержать:



```text

workflow\_dispatch

```



По возможности build для tag/release.



Использовать безопасный cache:



```text

downloads

toolchain

build cache

```



если это не ломает reproducibility.



GitHub Actions должен публиковать firmware artifacts.



\---



\# 48. ARTIFACTS



Собрать в:



```text

artifacts/

```



как минимум:



```text

sysupgrade image

sha256sums

config.buildinfo

feeds.buildinfo

version.buildinfo

packages.manifest

BUILD\_INFO.txt

```



Если возможно:



```text

SBOM

```



\---



\# 49. BUILD\_INFO



В:



```text

BUILD\_INFO.txt

```



записать:



```text

OPENWRT\_VERSION=

OPENWRT\_COMMIT=



KERNEL\_VERSION=



TARGET=

SUBTARGET=

DEVICE=



MT76\_SOURCE=

MT76\_COMMIT=



MAC80211\_VERSION=



MT7986\_FIRMWARE\_SOURCE=

MT7986\_FIRMWARE\_VERSION=



PESA\_REFERENCE\_BRANCH=

PESA\_REFERENCE\_COMMIT=



AMNEZIAWG\_VERSION=

AMNEZIAWG\_COMMIT=



PODKOP\_VERSION=

PODKOP\_COMMIT=



SING\_BOX\_VERSION=



BUILD\_DATE=

FIRMWARE\_SHA256=

```



\---



\# 50. FLINT2-INFO



Создай команду:



```bash

flint2-info

```



или:



```text

/usr/bin/flint2-info

```



которая выводит:



```text

OpenWrt

Kernel

mt76

Wi-Fi firmware

mac80211

wpad/hostapd

AmneziaWG

Podkop

sing-box

WED status

PPE status

Flow offload status

```



По возможности часть информации вывести через LuCI:



```text

Status → Flint 2

```



\---



\# 51. VERIFY-BUILD.SH



Создай:



```text

scripts/verify-build.sh

```



Проверить:



```text

\[ ] sysupgrade существует

\[ ] правильный device

\[ ] правильный target

\[ ] firmware не превышает допустимый размер



\[ ] LuCI присутствует

\[ ] HTTPS присутствует

\[ ] Russian LuCI присутствует



\[ ] kmod-amneziawg присутствует

\[ ] amneziawg-tools присутствует

\[ ] luci-proto-amneziawg присутствует



\[ ] podkop присутствует

\[ ] luci-app-podkop присутствует

\[ ] sing-box присутствует

\[ ] kmod-nft-tproxy присутствует



\[ ] WireGuard присутствует



\[ ] firewall4 присутствует

\[ ] nftables присутствует



\[ ] mt76 присутствует

\[ ] нужный MT7986 firmware присутствует



\[ ] PPPoE присутствует



\[ ] sha256 сформирован

```



\---



\# 52. HARDWARE-TEST.SH



Создай:



```text

scripts/hardware-test.sh

```



Для запуска на реальном Flint 2.



Проверять:



```text

CPU

RAM

temperature



kernel

mt76

Wi-Fi firmware



2.4 GHz

5 GHz



Ethernet

2.5 GbE



RTL8221B

MT7531



RSS

IRQ

WED

PPE

flow offload



WireGuard

AmneziaWG



Podkop

sing-box



firewall4

nftables

```



\---



\# 53. RUNTIME TEST AMNEZIAWG



В README:



```bash

uname -a



lsmod | grep -i amnezia



awg --version



ip link add awg-test type amneziawg

ip link show awg-test

ip link del awg-test

```



\---



\# 54. RUNTIME TEST PODKOP



Добавить актуальные команды проверки:



```bash

podkop show\_version



sing-box version



/etc/init.d/podkop status



nft list ruleset

```



Адаптировать под текущую версию Podkop.



\---



\# 55. WIFI DIAGNOSTICS



Добавить:



```bash

iw dev

iw phy



iwinfo



ubus call network.wireless status



dmesg | grep -Ei 'mt76|mt7915|mt7986|wed|wifi'



cat /proc/interrupts

cat /proc/softirqs

```



\---



\# 56. PODKOP ROUTING TEST



README должен описывать тест:



```text

1\. проверить public IP напрямую;



2\. создать AmneziaWG interface;



3\. проверить туннель;



4\. добавить тестовый домен в Podkop;



5\. проверить, что домен идёт через VPN;



6\. проверить, что другой ресурс остаётся DIRECT;



7\. проверить DNS leak;



8\. проверить после reboot.

```



\---



\# 57. PERFORMANCE TEST



Подготовить инструкции для:



```text

iperf3 LAN → LAN



iperf3 Wi-Fi → LAN



2.5GbE throughput



Wi-Fi latency



CPU load



IRQ distribution

```



Не делать вывод о качестве firmware только по Speedtest.



\---



\# 58. СРАВНИТЬ PESA PATCHES



В конце исследования вывести:



```text

=== PESA1234 ANALYSIS ===



Reference branch:

Reference commit:



Already upstream:

...



Included backports:

...



Included Pesa-specific patches:

...



Rejected patches:

...



Reason for rejection:

...

```



\---



\# 59. ОТЧЁТ ПО HARDWARE STACK



Также вывести:



```text

=== FLINT 2 HARDWARE STACK ===



OpenWrt:

Kernel:



mt76:

mac80211:

cfg80211:

wpad/hostapd:



MT7986 firmware:



RTL8221B:

MT7531:

mtk\_eth\_soc:



RSS:

WED:

PPE:



Software Flow Offload:

Hardware Flow Offload:



ATF:

HW-ATF:

iBF:

EDCCA:

256-QAM 2.4 GHz:



Known issues:

```



\---



\# 60. НЕ ТАЩИТЬ ЭКСПЕРИМЕНТЫ ВСЛЕПУЮ



Если patch:



```text

не upstream

не reviewed

имеет regressions

не используется активно

устарел

```



не включать автоматически.



Добавить его в HARDWARE\_STACK.md как:



```text

NOT INCLUDED

```



и объяснить почему.



\---



\# 61. ПРИОРИТЕТ ИСТОЧНИКОВ



Для исправлений использовать приоритет:



```text

1\. fix уже в stable OpenWrt



2\. fix уже merged в OpenWrt main

&#x20;  и безопасно backportable



3\. проверенный patch pesa1234 для GL-MT6000



4\. upstream MediaTek/Linux patch



5\. experimental code

```



Experimental использовать только при действительно серьёзной причине.



\---



\# 62. НЕ МАСКИРОВАТЬ BUILD ERRORS



Запрещено:



```text

\--force-depends

\--force-checksum

ручная подмена kernel ABI

ручная подмена vermagic

игнорирование failed packages

удаление проблемной функции молча

```



Исправлять корневую причину.



\---



\# 63. GUI CHECKLIST



На реальном роутере должно быть:



```text

\[ ] LuCI открывается

\[ ] HTTPS работает

\[ ] авторизация работает

\[ ] русский язык доступен



\[ ] WAN виден

\[ ] LAN виден

\[ ] Wi-Fi виден

\[ ] DHCP/DNS виден

\[ ] Firewall виден

\[ ] VLAN виден



\[ ] PPPoE можно создать



\[ ] WireGuard можно создать

\[ ] AmneziaWG можно создать



\[ ] Podkop есть в меню

\[ ] Podkop GUI работает



\[ ] Backup работает

\[ ] Flash Firmware работает

\[ ] Logs работают

\[ ] Diagnostics работают



\[ ] Flint 2 advanced settings отображают реальные функции

```



\---



\# 64. README



README.md должен быть полноценной пользовательской документацией:



```text

\# Flint 2 Custom OpenWrt



\## Что это



\## Hardware



\## Versions



\## Differences from vanilla OpenWrt



\## Pesa1234 patches



\## Wi-Fi stack



\## AmneziaWG



\## Podkop



\## Build locally



\## GitHub Actions



\## Firmware artifacts



\## Flash from GL.iNet firmware



\## Upgrade from OpenWrt



\## First boot



\## LuCI



\## Russian language



\## Configure Wi-Fi



\## Configure PPPoE



\## Configure WireGuard



\## Configure AmneziaWG



\## Configure Podkop



\## Split routing through AmneziaWG



\## Hardware acceleration



\## WED



\## Flow offload



\## Performance testing



\## Troubleshooting



\## Backup



\## Recovery



\## Restore GL.iNet firmware



\## Updating to a newer OpenWrt



\## Known Issues

```



\---



\# 65. ОБНОВЛЯЕМОСТЬ



Проект не должен быть одноразовым.



Например:



```bash

OPENWRT\_VERSION=

OPENWRT\_COMMIT=

AMNEZIAWG\_VERSION=

PODKOP\_VERSION=

```



должны задаваться централизованно.



При обновлении OpenWrt автоматически проверить:



```text

GL-MT6000 support

kernel

AmneziaWG build

Podkop build

sing-box compatibility

mt76 compatibility

patch applicability

```



\---



\# 66. РЕАЛЬНО СОБЕРИ



Не ограничивайся созданием scripts.



Если среда позволяет — реально выполни build.



При ошибках:



1\. изучи ошибку;

2\. исправь;

3\. повтори;

4\. продолжай до успешной сборки.



Не проси пользователя вручную разбираться с каждой ошибкой.



\---



\# 67. КРИТЕРИИ ГОТОВНОСТИ



Не считать задачу завершённой, пока:



```text

\[ ] firmware собирается



\[ ] device = GL-MT6000



\[ ] upstream OpenWrt используется как база



\[ ] актуальный MT7986 hardware stack выбран



\[ ] mt76 проверен и зафиксирован



\[ ] актуальный Wi-Fi firmware включён



\[ ] полезные pesa1234 improvements исследованы



\[ ] применённые Pesa patches документированы



\[ ] Ethernet 2.5G работает



\[ ] LuCI работает



\[ ] русский GUI работает



\[ ] AmneziaWG 2.x встроен



\[ ] AmneziaWG kernel ABI совпадает



\[ ] AmneziaWG GUI работает



\[ ] WireGuard работает



\[ ] Podkop встроен



\[ ] Podkop GUI работает



\[ ] sing-box встроен



\[ ] nftables / firewall4 работают



\[ ] TProxy работает



\[ ] Podkop + AmneziaWG selective routing работает



\[ ] WAN/LAN работают



\[ ] Wi-Fi 2.4 работает



\[ ] Wi-Fi 5 работает



\[ ] WPA2/WPA3 работают



\[ ] PPPoE работает



\[ ] IPv6 работает



\[ ] VLAN работает



\[ ] diagnostics доступны



\[ ] build reproducible



\[ ] GitHub Actions работает



\[ ] SHA256 создан



\[ ] README создан



\[ ] recovery документирован

```



\---



\# 68. ФИНАЛЬНАЯ АРХИТЕКТУРА



Целевая система:



```text

&#x20;                 GL.iNet Flint 2

&#x20;                    MT7986

&#x20;                      │

&#x20;             OpenWrt stable base

&#x20;                      │

&#x20;         ┌────────────┴────────────┐

&#x20;         │                         │

&#x20;     Wi-Fi stack              Ethernet stack

&#x20;         │                         │

&#x20;       mt76                   mtk\_eth\_soc

&#x20;         │                         │

&#x20; MT7986 firmware             MT7531 / RTL8221B

&#x20;         │                         │

&#x20;WED/RSS/BF/ATF               PPE / RSS / DSA

&#x20;         │                         │

&#x20;         └────────────┬────────────┘

&#x20;                      │

&#x20;               firewall4/nftables

&#x20;                      │

&#x20;              ┌───────┴───────┐

&#x20;              │               │

&#x20;            DIRECT          Podkop

&#x20;                              │

&#x20;                           sing-box

&#x20;                              │

&#x20;              ┌───────────────┴───────────────┐

&#x20;              │                               │

&#x20;         AmneziaWG                        other routes

&#x20;              │

&#x20;            VPN

```



Управление:



```text

&#x20;                   LuCI

&#x20;                    │

&#x20;    ┌───────────────┼─────────────────┐

&#x20;    │               │                 │

&#x20; Network          Podkop             VPN

&#x20;    │               │                 │

Wi-Fi/LAN/WAN    routing rules   WG / AmneziaWG

&#x20;    │

Flint 2 Advanced

&#x20;    │

WED / RSS / BF / ATF / offload

```



\---



\# 69. ФИНАЛЬНЫЙ ОТЧЁТ



После завершения не пиши огромный пересказ всей работы.



Выведи компактный технический итог:



```text

BUILD SUCCESS



Device:

GL.iNet Flint 2 GL-MT6000



OpenWrt:

...



Kernel:

...



Firmware:

...



SHA256:

...



mt76:

...



MT7986 firmware:

...



pesa1234 reference:

...



Pesa patches included:

...



AmneziaWG:

...



Podkop:

...



sing-box:

...



LuCI:

...



WED:

...



RSS:

...



PPE:

...



Hardware Flow Offload:

...



Known issues:

...

```



После этого дать:



```text

Firmware path:

...



How to flash:

...



First login:

...



How to configure AmneziaWG:

...



How to configure Podkop:

...

```



Работай автономно.



Не спрашивай пользователя подтверждения каждого технического решения.



Если обнаруживаешь более новую и технически лучшую реализацию, чем описана здесь:



1\. проверь её;

2\. используй её;

3\. зафиксируй источник и commit;

4\. объясни решение в документации.



Главная конечная цель:



\*\*получить максимально стабильную, современную и оптимизированную прошивку OpenWrt именно для Flint 2 GL-MT6000, с актуальным MediaTek/mt76 stack, проверенными улучшениями уровня pesa1234, полноценным русским LuCI, AmneziaWG 2.x и Podkop, которую можно прошить и нормально использовать как основной домашний роутер без постоянной работы через SSH.\*\*



