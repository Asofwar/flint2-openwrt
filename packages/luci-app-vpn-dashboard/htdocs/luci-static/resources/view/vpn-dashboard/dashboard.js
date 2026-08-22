'use strict';
'require view';
'require rpc';
'require fs';
'require ui';

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

function virtualAddress(entry) {
	var addresses = entry['ipv4-address'] || [];
	return addresses.length ? addresses[0].address : _('Not available');
}

function uptime(entry) {
	var seconds = entry.uptime || 0;
	if (!seconds)
		return _('Not available');
	if (seconds < 60)
		return '%d s'.format(seconds);
	if (seconds < 3600)
		return '%d min'.format(Math.floor(seconds / 60));
	return '%d h %d min'.format(Math.floor(seconds / 3600), Math.floor((seconds % 3600) / 60));
}

function lastHandshake(timestamp) {
	if (!timestamp)
		return _('Never');

	return new Date(timestamp * 1000).toLocaleString();
}

function protocolName(protocol) {
	return protocol === 'amneziawg' ? _('AmneziaWG') : _('WireGuard');
}

function containsInterface(sourceText, name, device) {
	return sourceText.split(/,\s*/).some(function(item) {
		return item === name || item === device;
	});
}

function tunnelAction(action, name) {
	return fs.exec('/usr/libexec/vpn-dashboard-tunnel', [ action, name ]).then(function(result) {
		if (result.code !== 0)
			throw new Error(result.stderr || _('The VPN tunnel command failed.'));
		window.location.reload();
	}).catch(function(error) {
		ui.addNotification(null, E('p', {}, error.message), 'error');
	});
}

function actionButton(label, action, name) {
	return E('button', {
		'class': 'btn cbi-button cbi-button-action',
		'click': function() { return tunnelAction(action, name); }
	}, label);
}

function tunnelCard(tunnel, interfaces, dashboard) {
	var state = interfaceState(interfaces, tunnel.name);
	var device = state.l3_device || tunnel.name;
	var stateText = tunnel.disabled ? _('Disabled') : (state.up ? _('Connected') : _('Disconnected'));
	var podkopUsage = containsInterface(dashboard.podkop_sources || '', tunnel.name, device) ? _('Source traffic') :
		(dashboard.podkop_outbound === tunnel.name || dashboard.podkop_outbound === device ? _('Selected outbound') : _('Not used'));
	var rows = [
		[ _('Protocol'), protocolName(tunnel.protocol) ],
		[ _('State'), stateText ],
		[ _('Interface'), device ],
		[ _('Endpoint'), tunnel.endpoint || _('Not configured') ],
		[ _('Virtual IP'), virtualAddress(state) ],
		[ _('Exit IP'), _('Not determined') ],
		[ _('Uptime'), uptime(state) ],
		[ _('Last handshake'), lastHandshake(tunnel.last_handshake) ],
		[ _('RX / TX'), traffic(state) ],
		[ _('MTU'), tunnel.mtu || _('Not configured') ],
		[ _('Podkop usage'), podkopUsage ]
	];

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, tunnel.name),
		E('table', { 'class': 'table' }, rows.map(function(row) {
			return E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, row[0]), E('td', { 'class': 'td left' }, row[1]) ]);
		})),
		E('p', {}, [
			actionButton(_('Connect'), 'up', tunnel.name), ' ',
			actionButton(_('Disconnect'), 'down', tunnel.name), ' ',
			actionButton(_('Restart'), 'restart', tunnel.name), ' ',
			E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': L.url('admin', 'network', 'network') }, _('Edit')), ' ',
			E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': L.url('admin', 'vpn', 'logs') }, _('Logs'))
		])
	]);
}

function routingDiagram(dashboard, services) {
	var podkopState = serviceState(services, 'podkop');
	var sources = dashboard.podkop_sources || _('Not configured');
	var outbound = dashboard.podkop_outbound || _('Direct');
	var connection = dashboard.podkop_connection_type || _('Direct');
	return E('pre', { 'class': 'cbi-section-descr' }, [
		'%s\n'.format(_('Traffic')),
		'  %s\n'.format(_('LAN/Wi-Fi and remote AmneziaWG clients')),
		'              |\n',
		'       Podkop: %s\n'.format(podkopState),
		'       sources: %s\n'.format(sources),
		'          /          \\\n',
		'     %s      %s: %s\n'.format(_('Direct'), connection, outbound),
		'                  sing-box'
	]);
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
			[ _('Podkop selected outbound'), dashboard.podkop_outbound || _('Direct') ],
			[ _('Podkop domain rules'), dashboard.podkop_domain_rules || 0 ],
			[ _('Podkop IP/subnet rules'), dashboard.podkop_subnet_rules || 0 ],
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
			E('h3', {}, _('Routing visualization')),
			routingDiagram(dashboard, services),
			E('h3', {}, _('VPN client tunnels')),
			dashboard.tunnels.length ? dashboard.tunnels.map(function(tunnel) { return tunnelCard(tunnel, interfaces, dashboard); }) : E('p', { 'class': 'cbi-section-descr' }, _('No outbound WireGuard or AmneziaWG tunnels are configured.')),
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
