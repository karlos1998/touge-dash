const $ = (selector) => document.querySelector(selector);
const tiles = [...document.querySelectorAll('.tile[data-key]')];
const precision = {
  afr: 1, tps: 0, clt_c: 0, oil_pressure_bar: 1, oil_temp_c: 0,
  battery_v: 1, iat_c: 0, fuel_pressure_bar: 1, ignition_deg: 1,
  injector_dc: 1, map_kpa: 0, lambda: 2,
};

function number(value, digits = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value.toFixed(digits) : '—';
}

function warning(key, value, data) {
  if (typeof value !== 'number') return false;
  if (key === 'clt_c') return value > 105;
  if (key === 'oil_temp_c') return value > 135;
  if (key === 'battery_v') return (data.rpm || 0) > 500 && value < 11.5;
  if (key === 'oil_pressure_bar') return (data.rpm || 0) > 1200 && value < .5;
  return false;
}

function render(payload) {
  const data = payload.telemetry || {};
  const connection = payload.connection || {};
  const age = data.age_s;
  const online = connection.status === 'connected' && typeof age === 'number' && age < 2;

  $('#source').textContent = connection.source || 'Bluetooth';
  const status = $('#status');
  status.className = `status ${online ? 'online' : connection.error ? 'error' : 'waiting'}`;
  status.querySelector('b').textContent = online ? 'ONLINE' : connection.status === 'reconnecting' ? 'PONAWIANIE' : 'OCZEKIWANIE';

  const rpm = typeof data.rpm === 'number' ? data.rpm : null;
  $('#rpm').textContent = number(rpm, 0);
  const ratio = Math.max(0, Math.min(1, (rpm || 0) / 9000));
  const rpmBar = $('#rpm-bar');
  rpmBar.style.width = `${ratio * 100}%`;
  rpmBar.style.background = (rpm || 0) >= 8000 ? 'var(--red)' : (rpm || 0) >= 7000 ? 'var(--amber)' : 'var(--cyan)';
  $('#boost').textContent = number(data.boost_bar, 2);
  $('#speed').textContent = number(data.speed_kmh, 0);
  $('#gear').textContent = number(data.gear, 0);

  for (const tile of tiles) {
    const key = tile.dataset.key;
    const value = data[key];
    tile.querySelector('strong').textContent = number(value, precision[key] || 0);
    tile.classList.toggle('warning', warning(key, value, data));
  }

  const celNames = Array.isArray(data.cel_names) ? data.cel_names : [];
  $('#cel').classList.toggle('hidden', !celNames.length);
  $('#cel span').textContent = celNames.join(' · ');
  $('#frames').textContent = `${connection.valid_frames || 0} poprawnych ramek`;
  $('#decoder').textContent = `Checksum: ${connection.bad_checksums || 0} błędów · Pominięte bajty: ${connection.dropped_bytes || 0}`;

  const pairing = $('#pairing');
  pairing.classList.toggle('hidden', online);
  const emuDevices = (payload.bluetooth_devices || []).filter((item) => /emu|ecumaster|canbt|btcan|edl/i.test(item.name));
  const ports = (payload.serial_ports || []).filter((port) => !/Incoming-Port|debug-console/i.test(port));
  const deviceList = $('#device-list');
  deviceList.replaceChildren();
  for (const item of emuDevices) {
    const row = document.createElement('div');
    const address = document.createElement('code');
    row.textContent = `${item.name} `;
    address.textContent = item.address;
    row.append(address);
    deviceList.append(row);
  }
  for (const port of ports) {
    const row = document.createElement('div');
    const code = document.createElement('code');
    code.textContent = port;
    row.append(code);
    deviceList.append(row);
  }
  if (!deviceList.childElementCount) deviceList.textContent = 'Nie wykryto jeszcze urządzenia EMU';
}

async function refresh() {
  try {
    const response = await fetch('/api/telemetry', { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
  } catch (error) {
    const status = $('#status');
    status.className = 'status error';
    status.querySelector('b').textContent = 'SERWER OFFLINE';
  }
}

refresh();
setInterval(refresh, 100);
