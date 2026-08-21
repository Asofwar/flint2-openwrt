'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';

var callInitAction = rpc.declare({
	object: 'luci',
	method: 'setInitAction',
	params: [ 'name', 'action' ],
	expect: { result: false }
});

function awgParameter(section, option, title, description) {
	var value = section.taboption('obfuscation', form.Value, option, title, description);
	value.optional = true;
	value.datatype = 'uinteger';
	return value;
}

function awgStringParameter(section, option, title, description) {
	var value = section.taboption('obfuscation', form.Value, option, title, description);
	value.optional = true;
	value.datatype = 'string';
	return value;
}

return view.extend({
	load: function() {
		return uci.load('vpn-dashboard');
	},

	handleSaveApply: function(ev, mode) {
		return this.handleSave(ev).then(function() {
			return callInitAction('vpn-dashboard', 'enable');
		}).then(function() {
			return callInitAction('vpn-dashboard', 'restart');
		}).then(function() {
			ui.changes.apply(mode == '0');
		});
	},

	render: function() {
		var map = new form.Map('vpn-dashboard', _('AmneziaWG Server'),
			_('The server uses a standard netifd AmneziaWG interface, firewall4 and Podkop. Saving does not expose keys in this page.'));
		var section = map.section(form.NamedSection, 'main', 'server', _('Server settings'));
		var option;

		option = section.option(form.Flag, 'enabled', _('Enable server'));
		option.default = option.disabled;
		option.rmempty = false;
		option = section.option(form.Value, 'address', _('Server address'));
		option.datatype = 'cidr4';
		option.rmempty = false;
		option.default = '10.77.0.1/24';
		option = section.option(form.Value, 'listen_port', _('Listen port'));
		option.datatype = 'port';
		option.rmempty = false;
		option.default = '51820';
		option = section.option(form.Value, 'mtu', _('MTU'));
		option.datatype = 'range(576,8940)';
		option.default = '1420';
		option = section.option(form.Flag, 'allow_internet', _('Allow Internet access'));
		option.default = option.enabled;
		option.rmempty = false;
		option = section.option(form.Flag, 'allow_lan', _('Allow access to home LAN'));
		option.default = option.enabled;
		option.rmempty = false;
		option = section.option(form.Flag, 'client_isolation', _('Isolate VPN clients'));
		option.default = option.enabled;
		option.rmempty = false;
		option = section.option(form.ListValue, 'podkop_policy', _('Traffic policy'));
		option.value('same_as_lan', _('Same as LAN / Podkop'));
		option.value('direct', _('Direct only'));
		option.default = 'same_as_lan';
		option.rmempty = false;
		option = section.option(form.ListValue, 'endpoint_mode', _('Client endpoint'));
		option.value('auto', _('Auto-detected WAN address'));
		option.value('ddns', _('DDNS hostname'));
		option.value('manual', _('Manual hostname or IP'));
		option.default = 'auto';
		option.rmempty = false;
		option = section.option(form.Value, 'endpoint_host', _('DDNS or manual endpoint'));
		option.datatype = 'string';
		option.depends('endpoint_mode', 'ddns');
		option.depends('endpoint_mode', 'manual');
		option.description = _('Required for client export when the WAN address is not directly reachable. Configure a DDNS service on the standard Services page when using a hostname.');

		section.tab('obfuscation', _('AmneziaWG obfuscation'));
		awgParameter(section, 'awg_jc', _('Jc'), _('Junk packet count. Leave unset when the provider does not supply a value.'));
		awgParameter(section, 'awg_jmin', _('Jmin'), _('Minimum junk packet size.'));
		awgParameter(section, 'awg_jmax', _('Jmax'), _('Maximum junk packet size.'));
		awgParameter(section, 'awg_s1', _('S1'), _('Handshake initiation junk header size.'));
		awgParameter(section, 'awg_s2', _('S2'), _('Handshake response junk header size.'));
		awgParameter(section, 'awg_s3', _('S3'), _('Cookie reply junk header size.'));
		awgParameter(section, 'awg_s4', _('S4'), _('Transport packet junk header size.'));
		awgStringParameter(section, 'awg_h1', _('H1'), _('AmneziaWG handshake header parameter.'));
		awgStringParameter(section, 'awg_h2', _('H2'), _('AmneziaWG handshake header parameter.'));
		awgStringParameter(section, 'awg_h3', _('H3'), _('AmneziaWG handshake header parameter.'));
		awgStringParameter(section, 'awg_h4', _('H4'), _('AmneziaWG handshake header parameter.'));
		awgStringParameter(section, 'awg_i1', _('I1'), _('Optional AmneziaWG 2.0 parameter.'));
		awgStringParameter(section, 'awg_i2', _('I2'), _('Optional AmneziaWG 2.0 parameter.'));
		awgStringParameter(section, 'awg_i3', _('I3'), _('Optional AmneziaWG 2.0 parameter.'));
		awgStringParameter(section, 'awg_i4', _('I4'), _('Optional AmneziaWG 2.0 parameter.'));
		awgStringParameter(section, 'awg_i5', _('I5'), _('Optional AmneziaWG 2.0 parameter.'));

		return map.render();
	}
});
