include $(TOPDIR)/rules.mk

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Андрей Зубченко

LUCI_TITLE:=LuCI VPN Dashboard for Flint 2
LUCI_DEPENDS:=+luci-base +amneziawg-tools +luci-proto-amneziawg +luci-app-podkop +firewall4 +podkop +jsonfilter +ip-full +qrencode +rpcd-mod-file
PKG_FILE_MODES:=/etc/init.d/vpn-dashboard:root:root:0755 /etc/hotplug.d/iface/90-vpn-dashboard:root:root:0755 /usr/libexec/vpn-dashboard-peer:root:root:0755 /usr/libexec/vpn-dashboard-sync-podkop:root:root:0755 /usr/libexec/vpn-dashboard-logs:root:root:0755 /usr/libexec/vpn-dashboard-tunnel:root:root:0755

define Package/luci-app-vpn-dashboard/conffiles
/etc/config/vpn-dashboard
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
