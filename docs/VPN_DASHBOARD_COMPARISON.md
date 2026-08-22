# Сравнение VPN Dashboard с UX GL.iNet

## Граница проекта

`flint2-openwrt` основан на upstream OpenWrt. Он не включает GL.iNet SDK,
`gl-sdk4-ui-vpndashboard`, `gl-sdk4-vpn-policy` или `gl-sdk4-wg-client`.
Интерфейс GL.iNet рассматривается только как UX-reference: официальная
[документация VPN Dashboard](https://github.com/gl-inet/docs4.x/blob/master/docs/en/docs/interface_guide/vpn_dashboard.md)
показывает модель «профиль → источник → назначение», а старое описание
[VPN Policies](https://github.com/gl-inet/docs3.x/blob/master/docs/tutorials/vpn_policies.md)
подтверждает domain/IP policy без необходимости переносить их proprietary
framework.

## Реализованное соответствие

| Пользовательский сценарий | Flint 2 OpenWrt | Основание |
| --- | --- | --- |
| outbound WireGuard / AmneziaWG | штатные netifd-протоколы LuCI | `luci-proto-wireguard`, `luci-proto-amneziawg` |
| selective routing | Podkop + sing-box + firewall4/nftables | отдельный `test-vm-podkop-policy.sh` проверяет DIRECT и VPN пути |
| AmneziaWG server | отдельный `awg_server`, отдельная firewall zone и WAN UDP rule | `luci-app-vpn-dashboard` |
| удалённые peer | create, export, QR, enable/disable, revoke, status RX/TX/handshake | `vpn-dashboard-peer` и LuCI Remote clients |
| политика удалённых клиентов | `Same as LAN / Podkop`: runtime L3 device через ubus добавляется в Podkop source interfaces | `vpn-dashboard-sync-podkop` |
| endpoint/DDNS | auto WAN, manual hostname/IP или стандартный OpenWrt DDNS | `ddns-scripts`, `luci-app-ddns` |
| CGNAT | предупреждение для private и CGNAT WAN address | главная страница Dashboard |
| безопасность API | status и Dashboard не возвращают private key или PSK | VM secret-leak test |

## Осознанные отличия

* Нет параллельного GL.iNet VPN-policy engine: источником истины для policy
  routing является Podkop.
* Нет proprietary cloud/account flows. Конфигурации импортируются и
  управляются штатными средствами OpenWrt.
* Kill Switch не включается автоматически: он влияет на доступность LAN/DNS и
  требует отдельной явно выбранной политики.
* Dashboard не подменяет страницы настройки обычных WireGuard/AmneziaWG
  client tunnels. Их lifecycle сохраняется за штатными LuCI/netifd,
  а Dashboard отвечает за обзор собственного AWG server и Podkop.

## Проверка поведения

Полный запуск в Windows PowerShell:

```powershell
.\test-vm.ps1
```

Он последовательно запускает runtime/reboot, внешний AWG outbound и
LAN-versus-remote Same Policy сценарии. Общий результат записывается в
`artifacts/test-results/<run-id>/summary.txt` и `junit.xml`.
