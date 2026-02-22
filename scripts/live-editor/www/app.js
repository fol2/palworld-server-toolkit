/* ── Palworld Live Editor V2 — Frontend ─────────────────────────────────────── */

const state = {
    players: [],
    selectedPlayer: null,
    playerSource: null,
    items: [],
    pals: [],
    palDb: {},
    selectedItem: null,
    selectedPal: null,
    waypoints: [],
    selectedWaypoint: null,
    commandLog: [],
    refreshTimer: 15,
    activeTab: 'players',
    logExpanded: true,
};

/* Category metadata */
const CAT = {
    boss:     { label: 'Boss',     color: '#EF4444' },
    dungeon:  { label: 'Dungeon',  color: '#A78BFA' },
    town:     { label: 'Town',     color: '#22D3EE' },
    base:     { label: 'Base',     color: '#34D399' },
    resource: { label: 'Resource', color: '#FBBF24' },
    custom:   { label: 'Custom',   color: '#60A5FA' },
};

/* ── API helpers ───────────────────────────────────────────────────────────── */

async function api(path, opts) {
    try {
        const res = await fetch(path, opts);
        return await res.json();
    } catch (e) {
        return null;
    }
}

const apiGet  = (path) => api(path);
const apiPost = (path, body) => api(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
});

/* Send a mod command and log the result */
async function sendCommand(type, params = {}, label) {
    if (label) addLog(label, 'info');
    const result = await apiPost('/api/command', { type, ...params });
    if (result && result.success) {
        addLog(result.message || 'OK', 'ok');
    } else {
        addLog('Failed: ' + (result ? result.message : 'No response'), 'err');
    }
    return result;
}

/* ── Tab switching ─────────────────────────────────────────────────────────── */

function switchTab(tabId) {
    state.activeTab = tabId;
    document.querySelectorAll('.tab').forEach(t =>
        t.classList.toggle('active', t.dataset.tab === tabId)
    );
    document.querySelectorAll('.tab-panel').forEach(p =>
        p.classList.toggle('active', p.id === 'tab-' + tabId)
    );
}

/* ── Status ─────────────────────────────────────────────────────────────────── */

async function refreshStatus() {
    const data = await apiGet('/api/status');
    const dot = document.getElementById('status-dot');
    const text = document.getElementById('status-text');
    const count = document.getElementById('player-count');
    const chipMod = document.getElementById('chip-mod');

    if (!data) {
        dot.className = 'chip-dot stopped';
        text.textContent = 'HTTP ERROR';
        return;
    }

    if (data.server_running) {
        dot.className = 'chip-dot running';
        text.textContent = 'RUNNING';
        const n = state.players.length;
        count.textContent = n + '/32';
    } else {
        dot.className = 'chip-dot stopped';
        text.textContent = 'STOPPED';
        count.textContent = '-/32';
    }

    // Mod status chip
    if (data.mod_status === 'enabled') {
        chipMod.textContent = 'MOD ON';
        chipMod.className = 'chip mod-on';
    } else if (data.mod_status === 'disabled') {
        chipMod.textContent = 'MOD OFF';
        chipMod.className = 'chip mod-off';
    } else {
        chipMod.textContent = '';
        chipMod.className = 'chip';
    }
}

/* ── Players ───────────────────────────────────────────────────────────────── */

async function refreshPlayers() {
    const data = await apiGet('/api/players');
    if (!data) return;

    state.players = data.players || [];
    state.playerSource = data.source || 'rcon';

    if (!state.selectedPlayer && state.players.length > 0) {
        state.selectedPlayer = state.players[0].name;
    }

    renderPlayers();
    renderPlayerActions();
    updateAllTargetDropdowns();
    updateSourceBadge();

    document.getElementById('online-count').textContent = state.players.length;
}

function renderPlayers() {
    const el = document.getElementById('player-list');
    if (state.players.length === 0) {
        el.innerHTML = '<div class="empty-state">No players online</div>';
        return;
    }

    const isRest = state.playerSource === 'rest_api';

    el.innerHTML = state.players.map(p => {
        const sel = p.name === state.selectedPlayer ? ' selected' : '';
        let metaHtml = '';
        if (isRest) {
            const parts = [];
            if (p.userId) parts.push(esc(p.userId));
            if (p.ping != null) {
                const ping = Math.round(p.ping);
                const cls = ping < 50 ? 'ping-good' : ping < 100 ? 'ping-mid' : 'ping-bad';
                parts.push('<span class="' + cls + '">' + ping + 'ms</span>');
            }
            if (p.location_x != null && p.location_y != null) {
                parts.push('<span class="mono">(' + Math.round(p.location_x) + ', ' + Math.round(p.location_y) + ')</span>');
            }
            if (parts.length > 0) {
                metaHtml = '<div class="player-meta">' + parts.join('<span class="sep"> | </span>') + '</div>';
            }
        }

        const levelHtml = isRest && p.level ? '<span class="player-level">Lv' + p.level + '</span>' : '';

        return '<div class="player-item' + sel + '" onclick="selectPlayer(\'' + esc(p.name) + '\')">' +
            '<span class="player-dot"></span>' +
            '<div class="player-info">' +
                '<div class="player-main">' +
                    '<span class="player-name">' + esc(p.name) + '</span>' +
                    levelHtml +
                '</div>' +
                metaHtml +
            '</div>' +
        '</div>';
    }).join('');
}

function renderPlayerActions() {
    const el = document.getElementById('player-actions-content');
    const p = state.players.find(pl => pl.name === state.selectedPlayer);

    if (!p) {
        el.innerHTML = '<div class="empty-state">Select a player from the list</div>';
        return;
    }

    const isRest = state.playerSource === 'rest_api';
    const pingText = (p.ping != null) ? Math.round(p.ping) + 'ms' : 'N/A';
    const locText = (p.location_x != null && p.location_y != null)
        ? '(' + Math.round(p.location_x) + ', ' + Math.round(p.location_y) + ')' : 'N/A';
    const levelText = p.level != null ? 'Lv' + p.level : '';
    const playerId = p.playerId || p.playeruid || '';

    let statsHtml = '';
    if (isRest) {
        statsHtml = '<div class="pa-stats">' + levelText + '  |  Ping: ' + pingText + '  |  Pos: ' + locText + '</div>';
    }

    el.innerHTML =
        '<div class="pa-header">' +
            '<div class="pa-name">' + esc(p.name) + '</div>' +
            statsHtml +
        '</div>' +

        '<div class="action-group">' +
            '<div class="action-group-label">Experience</div>' +
            '<div class="action-row">' +
                '<input type="number" id="exp-amount" class="input mono" value="1000" min="1" style="width:100px">' +
                '<button class="btn btn-accent btn-sm" onclick="giveExp()">Give EXP</button>' +
            '</div>' +
        '</div>' +

        '<div class="action-group">' +
            '<div class="action-group-label">Management</div>' +
            '<div class="action-row">' +
                '<button class="btn btn-danger btn-sm" onclick="modKickPlayer()">Kick</button>' +
                '<button class="btn btn-danger btn-sm" onclick="modBanPlayer()">Ban</button>' +
                '<button class="btn btn-sm" onclick="modSlayPlayer()">Slay</button>' +
            '</div>' +
        '</div>' +

        '<div class="action-group">' +
            '<div class="action-group-label">Unban (any player)</div>' +
            '<div class="action-row">' +
                '<input type="text" id="unban-name" class="input" value="' + esc(p.name) + '" style="flex:1">' +
                '<button class="btn btn-sm" onclick="modUnbanPlayer()">Unban</button>' +
            '</div>' +
        '</div>' +

        '<div class="action-group">' +
            '<div class="action-group-label">Powers</div>' +
            '<div class="action-row">' +
                '<button class="btn btn-sm" onclick="modFreezePlayer()">Freeze</button>' +
                '<button class="btn btn-sm" onclick="modUnfreezePlayer()">Unfreeze</button>' +
            '</div>' +
        '</div>' +

        '<div class="action-group">' +
            '<div class="action-group-label">Teleport</div>' +
            '<div class="action-row">' +
                '<button class="btn btn-sm" onclick="bringSelectedPlayer()">Bring to Me</button>' +
                '<button class="btn btn-sm" onclick="gotoSelectedPlayer()">Go to Player</button>' +
                '<button class="btn btn-sm" onclick="getSelectedPlayerPos()">Get Position</button>' +
            '</div>' +
        '</div>';
}

function updateSourceBadge() {
    const badge = document.getElementById('chip-source');
    if (state.playerSource === 'rest_api') {
        badge.textContent = 'REST';
        badge.className = 'chip rest';
    } else {
        badge.textContent = 'RCON';
        badge.className = 'chip rcon';
    }
}

function selectPlayer(name) {
    state.selectedPlayer = name;
    renderPlayers();
    renderPlayerActions();
    updateAllTargetDropdowns();
}

function updateAllTargetDropdowns() {
    const ids = ['give-target', 'spawn-target', 'tp-player', 'qt-player', 'world-target'];
    ids.forEach(id => {
        const sel = document.getElementById(id);
        if (!sel) return;
        const prev = sel.value;
        if (state.players.length === 0) {
            sel.innerHTML = '<option value="">No players</option>';
        } else {
            sel.innerHTML = state.players.map(p =>
                '<option value="' + esc(p.name) + '"' +
                (p.name === state.selectedPlayer ? ' selected' : '') +
                '>' + esc(p.name) + '</option>'
            ).join('');
        }
    });
}

/* ── Items ──────────────────────────────────────────────────────────────────── */

async function loadItems() {
    const data = await apiGet('/api/items');
    if (!data) return;
    state.items = Array.isArray(data) ? data : [];
    renderItems();
    document.getElementById('btn-give').disabled = false;
}

function renderItems(filter) {
    const el = document.getElementById('item-list');
    let items = state.items;

    if (filter) {
        const lf = filter.toLowerCase();
        items = items.filter(i =>
            i.name.toLowerCase().includes(lf) ||
            i.id.toLowerCase().includes(lf) ||
            (i.group && i.group.toLowerCase().includes(lf))
        );
    }

    if (items.length === 0) {
        el.innerHTML = '<div class="empty-state">No items found</div>';
        return;
    }

    const shown = items.slice(0, 200);
    el.innerHTML = shown.map(i => {
        const sel = i.id === (state.selectedItem && state.selectedItem.id) ? ' selected' : '';
        const group = i.group ? '<span class="item-group">' + esc(i.group) + '</span>' : '';
        return '<div class="list-item' + sel + '" onclick="selectItem(\'' + esc(i.id) + '\')">' +
            '<span class="item-name">' + esc(i.name) + '</span>' +
            group +
            '<span class="item-id">' + esc(i.id) + '</span>' +
        '</div>';
    }).join('');

    if (items.length > 200) {
        el.innerHTML += '<div class="empty-state">' + (items.length - 200) + ' more -- refine search</div>';
    }
}

function selectItem(id) {
    state.selectedItem = state.items.find(i => i.id === id) || null;
    renderItems(document.getElementById('give-search').value);
}

/* ── Pals ───────────────────────────────────────────────────────────────────── */

async function loadPals() {
    const data = await apiGet('/api/pals');
    if (!data) return;
    state.pals = Array.isArray(data) ? data : [];
    renderPals();
    document.getElementById('btn-spawn').disabled = false;
}

async function loadPalDb() {
    const data = await apiGet('/api/paldb');
    if (!data || !Array.isArray(data)) return;
    state.palDb = {};
    for (const p of data) {
        state.palDb[p.id] = p;
    }
    if (state.pals.length > 0) renderPals();
}

function renderPals(filter) {
    const el = document.getElementById('pal-list');
    let pals = state.pals;

    if (filter) {
        const lf = filter.toLowerCase();
        pals = pals.filter(p => {
            const db = state.palDb[p.id];
            const name = (db && db.name) || p.name;
            return name.toLowerCase().includes(lf) ||
                   p.id.toLowerCase().includes(lf) ||
                   p.name.toLowerCase().includes(lf);
        });
    }

    if (pals.length === 0) {
        el.innerHTML = '<div class="empty-state">No pals found</div>';
        return;
    }

    const hasPalDb = Object.keys(state.palDb).length > 0;
    const shown = pals.slice(0, 200);

    el.innerHTML = shown.map(p => {
        const sel = p.id === (state.selectedPal && state.selectedPal.id) ? ' selected' : '';
        const db = state.palDb[p.id];

        if (hasPalDb && db) {
            const boss = p.is_boss ? '<span class="pal-boss">BOSS</span>' : '';
            const elemHtml = (db.elements || []).map(e =>
                '<span class="element-badge" style="background:' + e.color + '33;color:' + e.color + '">' + esc(e.name) + '</span>'
            ).join(' ');
            const statsHtml = (db.hp != null)
                ? '<div class="pal-item-stats">HP ' + db.hp + ' | ATK ' + db.attack + ' | DEF ' + db.defense + '</div>' : '';
            const workEntries = db.work ? Object.entries(db.work) : [];
            const workHtml = workEntries.length > 0
                ? '<div class="pal-item-work">' + workEntries.map(([k, v]) => esc(k) + ' Lv' + v).join(', ') + '</div>' : '';

            return '<div class="pal-item-rich' + sel + '" onclick="selectPal(\'' + esc(p.id) + '\')">' +
                '<div class="pal-item-top">' +
                    elemHtml +
                    '<span class="item-name">' + esc(db.name) + '</span>' +
                    boss +
                    '<span class="item-id">' + esc(p.id) + '</span>' +
                '</div>' +
                statsHtml +
                workHtml +
            '</div>';
        } else {
            const boss = p.is_boss ? '<span class="pal-boss">BOSS</span>' : '';
            return '<div class="list-item' + sel + '" onclick="selectPal(\'' + esc(p.id) + '\')">' +
                '<span class="item-name">' + esc(p.name) + '</span>' +
                boss +
                '<span class="item-id">' + esc(p.id) + '</span>' +
            '</div>';
        }
    }).join('');

    if (pals.length > 200) {
        el.innerHTML += '<div class="empty-state">' + (pals.length - 200) + ' more -- refine search</div>';
    }
}

function selectPal(id) {
    state.selectedPal = state.pals.find(p => p.id === id) || null;
    renderPals(document.getElementById('spawn-search').value);
}

/* ── Waypoints ─────────────────────────────────────────────────────────────── */

async function loadWaypoints() {
    const data = await apiGet('/api/waypoints');
    if (!data) return;
    state.waypoints = data.waypoints || [];
    renderWaypoints();
    updateWaypointDropdown();
    document.getElementById('waypoint-count').textContent = state.waypoints.length;
}

function renderWaypoints() {
    const el = document.getElementById('waypoint-list');
    const searchEl = document.getElementById('wp-search');
    const catEl = document.getElementById('wp-cat-filter');
    const filter = searchEl ? searchEl.value.toLowerCase() : '';
    const catFilter = catEl ? catEl.value : '';

    let wps = state.waypoints;
    if (filter) {
        wps = wps.filter(w => w.name.toLowerCase().includes(filter));
    }
    if (catFilter) {
        wps = wps.filter(w => w.category === catFilter);
    }

    if (wps.length === 0) {
        el.innerHTML = '<div class="empty-state">No waypoints' + (filter || catFilter ? ' matching filter' : ' saved yet') + '</div>';
        return;
    }

    el.innerHTML = wps.map(w => {
        const sel = state.selectedWaypoint && state.selectedWaypoint.id === w.id ? ' selected' : '';
        const cat = CAT[w.category] || CAT.custom;
        const coords = Math.round(w.x) + ', ' + Math.round(w.y) + ', ' + Math.round(w.z);
        const deleteBtn = !w.preset
            ? '<button class="btn btn-danger btn-xs" onclick="event.stopPropagation();deleteWaypoint(\'' + esc(w.id) + '\')">Del</button>'
            : '';

        return '<div class="wp-item' + sel + '" onclick="selectWaypoint(\'' + esc(w.id) + '\')">' +
            '<span class="wp-cat-dot" style="background:' + cat.color + '"></span>' +
            '<div class="wp-info">' +
                '<div class="wp-name">' + esc(w.name) + '</div>' +
                '<div class="wp-coords">' + coords + '</div>' +
            '</div>' +
            '<span class="wp-cat-label" style="background:' + cat.color + '22;color:' + cat.color + '">' + cat.label + '</span>' +
            '<div class="wp-actions">' +
                '<button class="btn btn-xs" onclick="event.stopPropagation();gotoWaypoint(\'' + esc(w.id) + '\')" title="Admin go here">Go</button>' +
                deleteBtn +
            '</div>' +
        '</div>';
    }).join('');

    document.getElementById('waypoint-count').textContent = state.waypoints.length;
}

function selectWaypoint(id) {
    state.selectedWaypoint = state.waypoints.find(w => w.id === id) || null;
    renderWaypoints();
    // Fill coords
    if (state.selectedWaypoint) {
        const w = state.selectedWaypoint;
        document.getElementById('goto-x').value = Math.round(w.x);
        document.getElementById('goto-y').value = Math.round(w.y);
        document.getElementById('goto-z').value = Math.round(w.z);
    }
}

function updateWaypointDropdown() {
    const sel = document.getElementById('tp-waypoint');
    if (!sel) return;
    if (state.waypoints.length === 0) {
        sel.innerHTML = '<option value="">No waypoints</option>';
    } else {
        sel.innerHTML = state.waypoints.map(w =>
            '<option value="' + esc(w.id) + '">' + esc(w.name) + '</option>'
        ).join('');
    }
}

/* ── Waypoint Actions ──────────────────────────────────────────────────────── */

async function saveCurrentPosition() {
    const name = document.getElementById('wp-save-name').value.trim();
    const category = document.getElementById('wp-save-cat').value;
    if (!name) { addLog('Enter a waypoint name', 'err'); return; }

    addLog('Saving current position as "' + name + '"...', 'info');
    const result = await apiPost('/api/waypoints/save-pos', { name, category });
    if (result && result.success) {
        addLog(result.message, 'ok');
        document.getElementById('wp-save-name').value = '';
        loadWaypoints();
    } else {
        addLog('Failed: ' + (result ? result.message : 'No response'), 'err');
    }
}

async function deleteWaypoint(id) {
    const wp = state.waypoints.find(w => w.id === id);
    if (!wp || !confirm('Delete waypoint "' + wp.name + '"?')) return;

    const result = await apiPost('/api/waypoints', { action: 'delete', waypoint_id: id });
    if (result && result.success) {
        addLog('Deleted waypoint: ' + wp.name, 'ok');
        loadWaypoints();
    } else {
        addLog('Delete failed: ' + (result ? result.message : 'No response'), 'err');
    }
}

function gotoWaypoint(id) {
    const wp = state.waypoints.find(w => w.id === id);
    if (!wp) return;
    sendCommand('goto_coords', { x: wp.x, y: wp.y, z: wp.z },
        'Going to waypoint: ' + wp.name);
}

/* ── Command Actions ───────────────────────────────────────────────────────── */

/* Items */
async function giveItem() {
    const target = document.getElementById('give-target').value;
    const qty = parseInt(document.getElementById('give-qty').value) || 1;
    if (!state.selectedItem) { addLog('Select an item first', 'err'); return; }
    if (!target) { addLog('No target player', 'err'); return; }

    sendCommand('give_item',
        { target_player: target, item_id: state.selectedItem.id, quantity: qty },
        'Giving ' + qty + 'x ' + state.selectedItem.name + ' to ' + target + '...');
}

/* Pals */
async function spawnPal() {
    const target = document.getElementById('spawn-target').value;
    const level = parseInt(document.getElementById('spawn-level').value) || 1;
    if (!state.selectedPal) { addLog('Select a pal first', 'err'); return; }
    if (!target) { addLog('No target player', 'err'); return; }

    sendCommand('spawn_pal',
        { target_player: target, pal_id: state.selectedPal.id, level: level },
        'Spawning Lv' + level + ' ' + state.selectedPal.name + ' near ' + target + '...');
}

/* Experience */
function giveExp() {
    const amountEl = document.getElementById('exp-amount');
    if (!amountEl) return;
    const amount = parseInt(amountEl.value) || 1000;
    if (!state.selectedPlayer) { addLog('No player selected', 'err'); return; }
    sendCommand('give_exp',
        { target_player: state.selectedPlayer, amount: amount },
        'Giving ' + amount + ' EXP to ' + state.selectedPlayer + '...');
}

/* Player Management */
function modKickPlayer() {
    if (!state.selectedPlayer || !confirm('Kick ' + state.selectedPlayer + '?')) return;
    sendCommand('kick_player',
        { target_player: state.selectedPlayer },
        'Kicking ' + state.selectedPlayer + '...');
}

function modBanPlayer() {
    if (!state.selectedPlayer) return;
    const reason = prompt('Ban ' + state.selectedPlayer + '? Enter reason (optional):');
    if (reason === null) return;
    sendCommand('ban_player',
        { target_player: state.selectedPlayer, reason: reason },
        'Banning ' + state.selectedPlayer + '...');
}

function modUnbanPlayer() {
    const nameEl = document.getElementById('unban-name');
    const name = nameEl ? nameEl.value.trim() : '';
    if (!name) { addLog('Enter a player name to unban', 'err'); return; }
    if (!confirm('Unban ' + name + '?')) return;
    sendCommand('unban_player',
        { target_player: name },
        'Unbanning ' + name + '...');
}

function modSlayPlayer() {
    if (!state.selectedPlayer || !confirm('Slay ' + state.selectedPlayer + '?')) return;
    sendCommand('slay_player',
        { target_player: state.selectedPlayer },
        'Slaying ' + state.selectedPlayer + '...');
}

/* Powers */
function modFreezePlayer() {
    if (!state.selectedPlayer) { addLog('No player selected', 'err'); return; }
    sendCommand('freeze_player',
        { target_player: state.selectedPlayer },
        'Freezing ' + state.selectedPlayer + '...');
}

function modUnfreezePlayer() {
    if (!state.selectedPlayer) { addLog('No player selected', 'err'); return; }
    sendCommand('unfreeze_player',
        { target_player: state.selectedPlayer },
        'Unfreezing ' + state.selectedPlayer + '...');
}

/* Teleport */
function bringSelectedPlayer() {
    const qtSel = document.getElementById('qt-player');
    const name = (qtSel && qtSel.value) || state.selectedPlayer;
    if (!name) { addLog('No player selected', 'err'); return; }
    sendCommand('bring_player',
        { target_player: name },
        'Bringing ' + name + ' to admin...');
}

function gotoSelectedPlayer() {
    const qtSel = document.getElementById('qt-player');
    const targetName = (qtSel && qtSel.value) || state.selectedPlayer;
    const p = state.players.find(pl => pl.name === targetName);
    if (!p) { addLog('No player selected', 'err'); return; }
    if (p.location_x == null || p.location_y == null) {
        addLog('No coordinates available for ' + p.name + ' (need REST API)', 'err');
        return;
    }
    const z = p.location_z != null ? p.location_z : 0;
    sendCommand('goto_coords',
        { x: p.location_x, y: p.location_y, z: z },
        'Going to ' + p.name + '...');
}

function getSelectedPlayerPos() {
    if (!state.selectedPlayer) { addLog('No player selected', 'err'); return; }
    sendCommand('get_pos',
        { target_player: state.selectedPlayer },
        'Getting position of ' + state.selectedPlayer + ' (check in-game chat)...');
}

function gotoManualCoords() {
    const x = parseFloat(document.getElementById('goto-x').value) || 0;
    const y = parseFloat(document.getElementById('goto-y').value) || 0;
    const z = parseFloat(document.getElementById('goto-z').value) || 0;
    sendCommand('goto_coords', { x, y, z },
        'Going to (' + x + ', ' + y + ', ' + z + ')...');
}

function teleportPlayerToWaypoint() {
    const playerSel = document.getElementById('tp-player');
    const wpSel = document.getElementById('tp-waypoint');
    const playerName = playerSel ? playerSel.value : '';
    const wpId = wpSel ? wpSel.value : '';

    if (!playerName) { addLog('Select a player', 'err'); return; }
    if (!wpId) { addLog('Select a waypoint', 'err'); return; }

    const wp = state.waypoints.find(w => w.id === wpId);
    if (!wp) { addLog('Waypoint not found', 'err'); return; }

    sendCommand('teleport_player',
        { target_player: playerName, x: wp.x, y: wp.y, z: wp.z },
        'Teleporting ' + playerName + ' to ' + wp.name + '...');
}

function bringAllPlayers() {
    if (!confirm('Bring ALL players to your position?')) return;
    sendCommand('bring_all', {}, 'Bringing all players to admin...');
}

function adminUnstuck() {
    sendCommand('unstuck', {}, 'Unstuck (admin self)...');
}

/* World */
function setWorldTime(hour) {
    sendCommand('set_time', { hour: hour },
        'Setting time to ' + String(hour).padStart(2, '0') + ':00...');
}

function setTimeFromSlider() {
    const hour = parseInt(document.getElementById('time-slider').value) || 0;
    setWorldTime(hour);
}

function updateTimeSlider() {
    const val = document.getElementById('time-slider').value;
    document.getElementById('time-slider-val').textContent = String(val).padStart(2, '0') + ':00';
}

function getWorldTime() {
    sendCommand('get_time', {}, 'Getting current time (check in-game chat)...');
}

function sendAnnounce() {
    const msg = document.getElementById('announce-msg').value.trim();
    if (!msg) { addLog('Enter a message', 'err'); return; }
    sendCommand('announce', { message: msg }, 'Announcing: ' + msg);
    document.getElementById('announce-msg').value = '';
}

function flyToggle(enable) {
    sendCommand('fly_toggle', { enable: enable },
        (enable ? 'Enabling' : 'Disabling') + ' fly mode...');
}

function toggleSpectate() {
    sendCommand('spectate', {}, 'Toggling spectate mode...');
}

function getPlayerPos() {
    const target = document.getElementById('world-target').value;
    if (!target) { addLog('No player selected', 'err'); return; }
    sendCommand('get_pos', { target_player: target },
        'Getting position of ' + target + ' (check in-game chat)...');
}

/* ── RCON Commands ─────────────────────────────────────────────────────────── */

async function rconCmd(cmd) {
    addLog('RCON: ' + cmd, 'info');
    const result = await apiPost('/api/rcon', { command: cmd });
    if (result && result.success) {
        addLog('RCON OK: ' + (result.result || '(empty)'), 'ok');
    } else {
        addLog('RCON Error: ' + (result ? result.result : 'No response'), 'err');
    }
}

function rconBroadcast() {
    const msg = prompt('Broadcast message:');
    if (msg) rconCmd('Broadcast ' + msg.replace(/ /g, '_'));
}

function rconCustom() {
    const input = document.getElementById('rcon-input');
    const cmd = input.value.trim();
    if (!cmd) return;
    rconCmd(cmd);
    input.value = '';
}

/* ── Command Log ───────────────────────────────────────────────────────────── */

function addLog(msg, type) {
    const time = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    state.commandLog.unshift({ time, msg, type });
    if (state.commandLog.length > 100) state.commandLog.pop();
    renderLog();
}

function renderLog() {
    const el = document.getElementById('command-log');
    if (state.commandLog.length === 0) {
        el.innerHTML = '<div class="empty-state">No commands yet</div>';
        return;
    }
    el.innerHTML = state.commandLog.map(e =>
        '<div class="log-entry">' +
            '<span class="log-time">' + e.time + '</span>' +
            '<span class="log-msg log-' + e.type + '">' + esc(e.msg) + '</span>' +
        '</div>'
    ).join('');
}

function toggleLog() {
    state.logExpanded = !state.logExpanded;
    document.getElementById('command-log').classList.toggle('collapsed', !state.logExpanded);
    document.getElementById('log-toggle').classList.toggle('collapsed', !state.logExpanded);
}

/* ── Utility ───────────────────────────────────────────────────────────────── */

function esc(str) {
    if (!str) return '';
    const el = document.createElement('span');
    el.textContent = str;
    return el.innerHTML.replace(/'/g, '&#39;').replace(/"/g, '&quot;');
}

/* ── Initialisation ────────────────────────────────────────────────────────── */

document.addEventListener('DOMContentLoaded', () => {
    // Search filters
    document.getElementById('give-search').addEventListener('input', (e) => renderItems(e.target.value));
    document.getElementById('spawn-search').addEventListener('input', (e) => renderPals(e.target.value));
    document.getElementById('wp-search').addEventListener('input', () => renderWaypoints());
    document.getElementById('wp-cat-filter').addEventListener('change', () => renderWaypoints());

    // Action buttons
    document.getElementById('btn-give').addEventListener('click', giveItem);
    document.getElementById('btn-spawn').addEventListener('click', spawnPal);

    // RCON enter key
    document.getElementById('rcon-input').addEventListener('keydown', (e) => {
        if (e.key === 'Enter') rconCustom();
    });

    // Target dropdown sync
    const targetIds = ['give-target', 'spawn-target', 'tp-player', 'qt-player', 'world-target'];
    targetIds.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            el.addEventListener('change', (e) => {
                state.selectedPlayer = e.target.value;
                renderPlayers();
                renderPlayerActions();
                targetIds.forEach(otherId => {
                    if (otherId !== id) {
                        const other = document.getElementById(otherId);
                        if (other) other.value = e.target.value;
                    }
                });
            });
        }
    });

    // Load server info
    apiGet('/api/info').then(data => {
        if (data && data.server_name) {
            document.getElementById('server-name').textContent = data.server_name;
        }
    });

    // Initial load
    refreshStatus();
    refreshPlayers();
    loadItems();
    loadPals();
    loadPalDb();
    loadWaypoints();

    // Auto-refresh
    setInterval(() => {
        refreshPlayers();
        refreshStatus();
        state.refreshTimer = 15;
    }, 15000);

    // Countdown
    setInterval(() => {
        state.refreshTimer = Math.max(0, state.refreshTimer - 1);
        const el = document.getElementById('refresh-countdown');
        if (el) el.textContent = state.refreshTimer;
    }, 1000);
});
