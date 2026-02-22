/* ── Palworld Live Editor — Frontend ────────────────────────────────────────── */

const state = {
    players: [],
    selectedPlayer: null,
    playerSource: null,
    items: [],
    pals: [],
    palDb: {},
    selectedItem: null,
    selectedPal: null,
    commandLog: [],
    refreshTimer: 15,
};

/* ── API helpers ────────────────────────────────────────────────────────────── */

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

/* ── Status ─────────────────────────────────────────────────────────────────── */

async function refreshStatus() {
    const data = await apiGet('/api/status');
    const dot = document.getElementById('status-dot');
    const text = document.getElementById('status-text');
    const count = document.getElementById('player-count');

    if (!data) {
        dot.className = 'dot stopped';
        text.textContent = 'HTTP ERROR';
        return;
    }

    if (data.server_running) {
        dot.className = 'dot running';
        text.textContent = 'RUNNING';
        const n = state.players.length;
        count.textContent = `${n}/32`;
    } else {
        dot.className = 'dot stopped';
        text.textContent = 'STOPPED';
        count.textContent = '';
    }
}

/* ── Players ────────────────────────────────────────────────────────────────── */

async function refreshPlayers() {
    const data = await apiGet('/api/players');
    if (!data) return;

    state.players = data.players || [];
    state.playerSource = data.source || 'rcon';

    // Auto-select first player if none selected
    if (!state.selectedPlayer && state.players.length > 0) {
        state.selectedPlayer = state.players[0].name;
    }

    renderPlayers();
    renderPlayerDetail();
    updateTargetDropdowns();
    updateSourceBadge();
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
                parts.push(`<span class="${cls}">${ping}ms</span>`);
            }
            if (p.location_x != null && p.location_y != null) {
                parts.push(`(${Math.round(p.location_x)}, ${Math.round(p.location_y)})`);
            }
            if (parts.length > 0) {
                metaHtml = `<div class="player-meta">${parts.join('<span class="sep">|</span>')}</div>`;
            }
        }

        const levelHtml = isRest && p.level ? `<span class="player-level">Lv ${p.level}</span>` : '';

        return `<div class="player-item${sel}" onclick="selectPlayer('${esc(p.name)}')">
            <span class="player-dot"></span>
            <div class="player-info">
                <div class="player-main">
                    <span class="player-name">${esc(p.name)}</span>
                    ${levelHtml}
                </div>
                ${metaHtml}
            </div>
        </div>`;
    }).join('');
}

function renderPlayerDetail() {
    const el = document.getElementById('player-detail');
    if (!el) return;

    const p = state.players.find(pl => pl.name === state.selectedPlayer);
    if (!p || state.playerSource !== 'rest_api') {
        el.classList.add('hidden');
        return;
    }

    el.classList.remove('hidden');

    const pingHtml = p.ping != null ? `${Math.round(p.ping)}ms` : 'N/A';
    const locHtml = (p.location_x != null && p.location_y != null)
        ? `(${Math.round(p.location_x)}, ${Math.round(p.location_y)})` : 'N/A';
    const playerId = p.playerId || p.playeruid || '';
    const shortId = playerId.length > 12 ? playerId.substring(0, 12) + '...' : playerId;

    el.innerHTML = `
        <div class="player-detail-name">${esc(p.name)}</div>
        <div class="player-detail-row">Level: <span>${esc(String(p.level ?? 'N/A'))}</span>  |  Platform: <span>${esc(p.userId || 'N/A')}</span></div>
        <div class="player-detail-row">Ping: <span>${pingHtml}</span>  |  Location: <span>${locHtml}</span></div>
        <div class="player-detail-row">Player ID: <span title="${esc(playerId)}">${esc(shortId)}</span></div>
        <div class="player-detail-actions">
            <button class="btn btn-sm btn-danger" onclick="kickPlayer('${esc(playerId)}')">Kick</button>
            <button class="btn btn-sm btn-danger" onclick="banPlayer('${esc(playerId)}')">Ban</button>
        </div>
    `;
}

function updateSourceBadge() {
    const badge = document.getElementById('source-badge');
    if (!badge) return;
    if (state.playerSource === 'rest_api') {
        badge.textContent = 'REST';
        badge.className = 'source-badge rest';
    } else {
        badge.textContent = 'RCON';
        badge.className = 'source-badge rcon';
    }
}

function selectPlayer(name) {
    state.selectedPlayer = name;
    renderPlayers();
    renderPlayerDetail();
    updateTargetDropdowns();
}

function updateTargetDropdowns() {
    ['give-target', 'spawn-target'].forEach(id => {
        const sel = document.getElementById(id);
        const prev = sel.value;
        sel.innerHTML = state.players.map(p =>
            `<option value="${esc(p.name)}"${p.name === state.selectedPlayer ? ' selected' : ''}>${esc(p.name)}</option>`
        ).join('');
        // If no players, add placeholder
        if (state.players.length === 0) {
            sel.innerHTML = '<option value="">No players</option>';
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

    // Limit render for performance
    const shown = items.slice(0, 200);
    el.innerHTML = shown.map(i => {
        const sel = i.id === (state.selectedItem && state.selectedItem.id) ? ' selected' : '';
        const group = i.group ? `<span class="item-group">${esc(i.group)}</span>` : '';
        return `<div class="list-item${sel}" onclick="selectItem('${esc(i.id)}')">
            <span class="item-name">${esc(i.name)}</span>
            ${group}
            <span class="item-id">${esc(i.id)}</span>
        </div>`;
    }).join('');

    if (items.length > 200) {
        el.innerHTML += `<div class="empty-state">${items.length - 200} more — refine search</div>`;
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
    // Re-render pals if already loaded
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
            // Enriched rendering
            const boss = p.is_boss ? '<span class="pal-boss">BOSS</span>' : '';
            const elemHtml = (db.elements || []).map(e =>
                `<span class="element-badge" style="background:${e.color}33;color:${e.color}">${esc(e.name)}</span>`
            ).join(' ');
            const statsHtml = (db.hp != null)
                ? `<div class="pal-item-stats">HP ${db.hp} | ATK ${db.attack} | DEF ${db.defense}</div>` : '';
            const workEntries = db.work ? Object.entries(db.work) : [];
            const workHtml = workEntries.length > 0
                ? `<div class="pal-item-work">${workEntries.map(([k, v]) => `${esc(k)} Lv${v}`).join(', ')}</div>` : '';

            return `<div class="pal-item-rich${sel}" onclick="selectPal('${esc(p.id)}')">
                <div class="pal-item-top">
                    ${elemHtml}
                    <span class="item-name">${esc(db.name)}</span>
                    ${boss}
                    <span class="item-id">${esc(p.id)}</span>
                </div>
                ${statsHtml}
                ${workHtml}
            </div>`;
        } else {
            // Basic rendering (fallback)
            const boss = p.is_boss ? '<span class="pal-boss">BOSS</span>' : '';
            return `<div class="list-item${sel}" onclick="selectPal('${esc(p.id)}')">
                <span class="item-name">${esc(p.name)}</span>
                ${boss}
                <span class="item-id">${esc(p.id)}</span>
            </div>`;
        }
    }).join('');

    if (pals.length > 200) {
        el.innerHTML += `<div class="empty-state">${pals.length - 200} more — refine search</div>`;
    }
}

function selectPal(id) {
    state.selectedPal = state.pals.find(p => p.id === id) || null;
    renderPals(document.getElementById('spawn-search').value);
}

/* ── Command Log ────────────────────────────────────────────────────────────── */

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
        `<div class="log-entry">
            <span class="log-time">${e.time}</span>
            <span class="log-msg log-${e.type}">${esc(e.msg)}</span>
        </div>`
    ).join('');
}

/* ── Actions ────────────────────────────────────────────────────────────────── */

async function giveItem() {
    const target = document.getElementById('give-target').value;
    const qty = parseInt(document.getElementById('give-qty').value) || 1;
    if (!state.selectedItem) { addLog('Select an item first', 'err'); return; }
    if (!target) { addLog('No target player', 'err'); return; }

    addLog(`Giving ${qty}x ${state.selectedItem.name} to ${target}...`, 'info');

    const result = await apiPost('/api/command', {
        type: 'give_item',
        target_player: target,
        item_id: state.selectedItem.id,
        quantity: qty,
    });

    if (result && result.success) {
        addLog(`${result.message}`, 'ok');
    } else {
        addLog(`Failed: ${result ? result.message : 'No response'}`, 'err');
    }
}

async function spawnPal() {
    const target = document.getElementById('spawn-target').value;
    const level = parseInt(document.getElementById('spawn-level').value) || 1;
    if (!state.selectedPal) { addLog('Select a pal first', 'err'); return; }
    if (!target) { addLog('No target player', 'err'); return; }

    addLog(`Spawning Lv${level} ${state.selectedPal.name} near ${target}...`, 'info');

    const result = await apiPost('/api/command', {
        type: 'spawn_pal',
        target_player: target,
        pal_id: state.selectedPal.id,
        level: level,
    });

    if (result && result.success) {
        addLog(`${result.message}`, 'ok');
    } else {
        addLog(`Failed: ${result ? result.message : 'No response'}`, 'err');
    }
}

/* ── RCON Commands ──────────────────────────────────────────────────────────── */

async function rconCmd(cmd) {
    addLog(`RCON: ${cmd}`, 'info');
    const result = await apiPost('/api/rcon', { command: cmd });
    if (result && result.success) {
        addLog(`RCON OK: ${result.result || '(empty)'}`, 'ok');
    } else {
        addLog(`RCON Error: ${result ? result.result : 'No response'}`, 'err');
    }
}

async function kickPlayer(playerId) {
    if (!playerId || !confirm(`Kick player ${playerId}?`)) return;
    addLog(`Kicking player ${playerId}...`, 'info');
    const result = await apiPost('/api/rcon', { command: `KickPlayer ${playerId}` });
    if (result && result.success) {
        addLog(`Kick OK: ${result.result || '(empty)'}`, 'ok');
    } else {
        addLog(`Kick Error: ${result ? result.result : 'No response'}`, 'err');
    }
}

async function banPlayer(playerId) {
    if (!playerId || !confirm(`Ban player ${playerId}? This cannot be easily undone.`)) return;
    addLog(`Banning player ${playerId}...`, 'info');
    const result = await apiPost('/api/rcon', { command: `BanPlayer ${playerId}` });
    if (result && result.success) {
        addLog(`Ban OK: ${result.result || '(empty)'}`, 'ok');
    } else {
        addLog(`Ban Error: ${result ? result.result : 'No response'}`, 'err');
    }
}

function rconBroadcast() {
    const msg = prompt('Broadcast message:');
    if (msg) rconCmd(`Broadcast ${msg.replace(/ /g, '_')}`);
}

function rconCustom() {
    const input = document.getElementById('rcon-input');
    const cmd = input.value.trim();
    if (!cmd) return;
    rconCmd(cmd);
    input.value = '';
}

/* ── Utility ────────────────────────────────────────────────────────────────── */

function esc(str) {
    if (!str) return '';
    const el = document.createElement('span');
    el.textContent = str;
    return el.innerHTML.replace(/'/g, '&#39;');
}

/* ── Initialisation ─────────────────────────────────────────────────────────── */

document.addEventListener('DOMContentLoaded', () => {
    // Search filters
    document.getElementById('give-search').addEventListener('input', (e) => {
        renderItems(e.target.value);
    });
    document.getElementById('spawn-search').addEventListener('input', (e) => {
        renderPals(e.target.value);
    });

    // Action buttons
    document.getElementById('btn-give').addEventListener('click', giveItem);
    document.getElementById('btn-spawn').addEventListener('click', spawnPal);

    // RCON enter key
    document.getElementById('rcon-input').addEventListener('keydown', (e) => {
        if (e.key === 'Enter') rconCustom();
    });

    // Target dropdown sync
    document.getElementById('give-target').addEventListener('change', (e) => {
        state.selectedPlayer = e.target.value;
        renderPlayers();
        document.getElementById('spawn-target').value = e.target.value;
    });
    document.getElementById('spawn-target').addEventListener('change', (e) => {
        state.selectedPlayer = e.target.value;
        renderPlayers();
        document.getElementById('give-target').value = e.target.value;
    });

    // Load server info (name)
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

    // Auto-refresh timers
    setInterval(() => {
        refreshPlayers();
        refreshStatus();
        state.refreshTimer = 15;
    }, 15000);

    // Countdown display
    setInterval(() => {
        state.refreshTimer = Math.max(0, state.refreshTimer - 1);
        const el = document.getElementById('refresh-countdown');
        if (el) el.textContent = state.refreshTimer;
    }, 1000);
});
