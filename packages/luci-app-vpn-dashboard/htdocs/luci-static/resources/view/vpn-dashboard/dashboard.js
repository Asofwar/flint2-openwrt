'use strict';
'require view';
'require rpc';
'require fs';

var callInterfaceDump = rpc.declare({
	object: 'network.interface',
	method: 'dump',
	expect: { interface: [] }
});

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	expect: {}
});

function serviceState(services, name) {
	var instances = services[name] && services[name].instances;
	if (!instances)
		return _('Not installed');

	return Object.keys(instances).some(function(instance) {
		return instances[instance].running;
	}) ? _('Running') : _('Stopped');
}

function interfaceState(interfaces, name) {
	return interfaces.find(function(entry) { return entry.interface === name; }) || {};
}

function traffic(entry) {
	var stats = entry.data && entry.data.statistics;
	if (!stats)
		return _('No data');

	return '%s / %s'.format(L.formatBytes(stats.rx_bytes || 0), L.formatBytes(stats.tx_bytes || 0));
}

return view.extend({
	load: function() {
		return Promise.all([
			callInterfaceDump(),
			callServiceList(),
			fs.exec('/usr/libexec/vpn-dashboard-peer', [ 'dashboard' ]).then(function(result) {
				if (result.code !== 0)
					throw new Error(result.stderr || _('Unable to read VPN Dashboard state.'));
				return JSON.parse(result.stdout);
			}),
			fs.exec('/usr/libexec/vpn-dashboard-peer', [ 'status' ]).then(function(result) {
				if (result.code !== 0)
					throw new Error(result.stderr || _('Unable to read VPN peer state.'));
				return JSON.parse(result.stdout);
			})
		]);
	},

	render: function(data) {
		var interfaces = data[0], services = data[1], dashboard = data[2], peerStatus = data[3];
		var configured = dashboard.server_enabled;
		var interfaceName = dashboard.interface || 'awg_server';
		var awg = interfaceState(interfaces, interfaceName);
		var sourceText = dashboard.podkop_sources;
		var onlinePeers = peerStatus.peers.filter(function(peer) { return peer.online; }).length;
		var cgnatWarning = dashboard.cgnat ? E('div', { class: 'alert-message warning' }, _('The WAN address is private or CGNAT. Incoming AmneziaWG connections may not be reachable directly.')) : '';
		var rows = [
			[ _('WAN address'), dashboard.wan_address || _('Not configured') ],
			[ _('AmneziaWG server'), configured ? (awg.up ? _('Running') : _('Configured, waiting for interface')) : _('Disabled') ],
			[ _('Server interface'), awg.l3_device || interfaceName ],
			[ _('Server traffic (RX / TX)'), traffic(awg) ],
			[ _('Remote peers'), '%d / %d %s'.format(onlinePeers, peerStatus.peers.length, _('online')) ],
			[ _('Podkop'), serviceState(services, 'podkop') ],
			[ _('Podkop source interfaces'), sourceText || _('Not configured') ],
			[ _('sing-box'), serviceState(services, 'sing-box') ]
		];

		return E([], [
			E('h2', {}, _('VPN Dashboard')),
			E('p', {}, _('This page shows only operational state. Private keys and preshared keys are never displayed.')),
			cgnatWarning,
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('Component')), E('th', { 'class': 'th' }, _('State')) ])
			].concat(rows.map(function(row) {
				return E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td' }, row[0]), E('td', { 'class': 'td' }, row[1]) ]);
			}))),
			E('p', {}, [
				E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': L.url('admin', 'vpn', 'amneziawg-server') }, _('Configure AmneziaWG server')),
				' ',
				E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': L.url('admin', 'services', 'podkop') }, _('Configure Podkop')),
				' ',
				E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': L.url('admin', 'vpn', 'logs') }, _('VPN Logs'))
			])
		]);
	}
});
