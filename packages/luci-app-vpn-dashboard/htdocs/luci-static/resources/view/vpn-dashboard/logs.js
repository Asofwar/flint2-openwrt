'use strict';
'require view';
'require fs';

var logCommand = '/usr/libexec/vpn-dashboard-logs';

function readLogs(filter) {
	return fs.exec(logCommand, [ filter ]).then(function(result) {
		if (result.code !== 0)
			throw new Error(result.stderr || _('Unable to read VPN logs.'));
		return result.stdout;
	});
}

return view.extend({
	load: function() {
		return readLogs('all');
	},

	render: function(output) {
		var select = E('select', { class: 'cbi-input-select' }, [
			E('option', { value: 'all' }, _('All VPN components')),
			E('option', { value: 'server' }, _('AmneziaWG server')),
			E('option', { value: 'podkop' }, _('Podkop and sing-box')),
			E('option', { value: 'wireguard' }, _('WireGuard and AmneziaWG'))
		]);
		var log = E('textarea', { class: 'cbi-input-textarea', readonly: 'readonly', rows: 24 }, [ output || _('No matching log entries.') ]);

		select.addEventListener('change', function() {
			readLogs(select.value).then(function(text) {
				log.value = text || _('No matching log entries.');
			}).catch(function(error) {
				log.value = error.message;
			});
		});

		return E([], [
			E('h2', {}, _('VPN Logs')),
			E('p', {}, _('Only VPN-related system logs are shown. Lines containing credentials or keys are excluded.')),
			E('div', { class: 'cbi-value' }, [ E('label', { class: 'cbi-value-title' }, _('Component')), E('div', { class: 'cbi-value-field' }, [ select ]) ]),
			log
		]);
	}
});
