'use strict';
'require view';
'require fs';
'require ui';

var peerCommand = '/usr/libexec/vpn-dashboard-peer';

function runPeerCommand(args) {
	return fs.exec(peerCommand, args).then(function(result) {
		if (result.code !== 0)
			throw new Error(result.stderr || _('The VPN server command failed.'));
		return result.stdout;
	});
}

function formatBytes(value) {
	return L.formatBytes(+value || 0);
}

function renderConfiguration(title, name, configuration) {
	var objectUrl = URL.createObjectURL(new Blob([ configuration ], { type: 'text/plain;charset=utf-8' }));
	ui.showModal(title, [
		E('p', {}, _('This configuration contains the client private key. Store it securely and do not share it.')),
		E('textarea', { class: 'cbi-input-textarea', readonly: 'readonly', rows: 18 }, [ configuration ]),
		E('div', { class: 'right' }, [
			E('a', { class: 'btn cbi-button cbi-button-action', href: objectUrl, download: '%s.conf'.format(name) }, _('Download .conf')),
			' ',
			E('button', { class: 'btn', click: function() { URL.revokeObjectURL(objectUrl); ui.hideModal(); } }, _('Close'))
		])
	]);
}

return view.extend({
	load: function() {
		return runPeerCommand([ 'status' ]).then(function(output) {
			return JSON.parse(output);
		});
	},

	showQr: function(peer) {
		return runPeerCommand([ 'qr', peer.id ]).then(function(svg) {
			ui.showModal(_('QR code: %s').format(peer.name), [
				E('p', {}, _('Scan this code only on the trusted client that will use this VPN profile.')),
				E('img', { alt: _('Client QR code'), src: 'data:image/svg+xml;base64,' + svg, style: 'max-width: 100%; height: auto;' }),
				E('div', { class: 'right' }, [ E('button', { class: 'btn', click: ui.hideModal }, _('Close')) ])
			]);
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message), 'error');
		});
	},

	exportPeer: function(peer) {
		return runPeerCommand([ 'export', peer.id ]).then(function(configuration) {
			renderConfiguration(_('Client configuration: %s').format(peer.name), peer.name, configuration);
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message), 'error');
		});
	},

	setEnabled: function(peer, enabled) {
		return runPeerCommand([ 'enable', peer.id, enabled ? '1' : '0' ]).then(function() {
			window.location.reload();
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message), 'error');
		});
	},

	deletePeer: function(peer) {
		ui.showModal(_('Revoke client: %s').format(peer.name), [
			E('p', {}, _('The client will lose access immediately after the server configuration is applied.')),
			E('div', { class: 'right' }, [
				E('button', { class: 'btn', click: ui.hideModal }, _('Cancel')),
				' ',
				E('button', { class: 'btn cbi-button cbi-button-negative', click: L.bind(function() {
					return runPeerCommand([ 'delete', peer.id ]).then(function() { window.location.reload(); });
				}, this) }, _('Revoke'))
			])
		]);
	},

	addPeer: function() {
		var name = E('input', { class: 'cbi-input-text', type: 'text', maxlength: 32, placeholder: 'iPhone' });
		var mode = E('select', { class: 'cbi-input-select' }, [
			E('option', { value: 'full', selected: 'selected' }, _('Internet through Flint 2')),
			E('option', { value: 'home' }, _('Home network only'))
		]);
		ui.showModal(_('Add client'), [
			E('div', { class: 'cbi-value' }, [ E('label', { class: 'cbi-value-title' }, _('Name')), E('div', { class: 'cbi-value-field' }, [ name ]) ]),
			E('div', { class: 'cbi-value' }, [ E('label', { class: 'cbi-value-title' }, _('Access profile')), E('div', { class: 'cbi-value-field' }, [ mode ]) ]),
			E('p', {}, _('The address is allocated automatically. The private key is shown only once in the following export step.')),
			E('div', { class: 'right' }, [
				E('button', { class: 'btn', click: ui.hideModal }, _('Cancel')),
				' ',
				E('button', { class: 'btn cbi-button cbi-button-positive important', click: L.bind(function() {
					return runPeerCommand([ 'create', name.value, mode.value ]).then(function(configuration) {
						renderConfiguration(_('New client configuration'), name.value, configuration);
					}).catch(function(error) {
						ui.addNotification(null, E('p', {}, error.message), 'error');
					});
				}, this) }, _('Create client'))
			])
		]);
	},

	render: function(status) {
		var rows = status.peers.map(L.bind(function(peer) {
			return [
				peer.name,
				peer.address,
				peer.public_key,
				peer.enabled ? _('Enabled') : _('Disabled'),
				peer.online ? _('Online') : _('Offline'),
				peer.last_handshake ? new Date(peer.last_handshake * 1000).toLocaleString() : _('Never'),
				'%s / %s'.format(formatBytes(peer.rx), formatBytes(peer.tx)),
				E('div', { class: 'cbi-section-actions' }, [
					E('button', { class: 'btn cbi-button cbi-button-action', click: L.bind(this.exportPeer, this, peer) }, _('Show / download')),
					' ', E('button', { class: 'btn cbi-button cbi-button-action', click: L.bind(this.showQr, this, peer) }, _('Show QR')),
					' ', E('button', { class: 'btn', click: L.bind(this.setEnabled, this, peer, !peer.enabled) }, peer.enabled ? _('Disable') : _('Enable')),
					' ', E('button', { class: 'btn cbi-button-negative', click: L.bind(this.deletePeer, this, peer) }, _('Revoke'))
				])
			];
		}, this));

		return E([], [
			E('h2', {}, _('AmneziaWG remote clients')),
			E('p', {}, _('Clients are attached to the dedicated awg_server interface and inherit its firewall and Podkop policy. Status output never contains private or preshared keys.')),
			E('div', { class: 'cbi-section-actions' }, [ E('button', { class: 'btn cbi-button cbi-button-add', click: L.bind(this.addPeer, this) }, _('Add client')) ]),
			E('div', { class: 'table' }, [
				E('div', { class: 'tr table-titles' }, [
					E('div', { class: 'th' }, _('Name')), E('div', { class: 'th' }, _('Assigned IP')), E('div', { class: 'th' }, _('Public key')),
					E('div', { class: 'th' }, _('State')), E('div', { class: 'th' }, _('Online')), E('div', { class: 'th' }, _('Last handshake')),
					E('div', { class: 'th' }, _('RX / TX')), E('div', { class: 'th' }, _('Actions'))
				]),
				rows.map(function(row) { return E('div', { class: 'tr' }, row.map(function(cell) { return E('div', { class: 'td' }, [ cell ]); })); })
			])
		]);
	}
});
