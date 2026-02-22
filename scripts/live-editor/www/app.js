/* ── Palworld Live Editor V2 — Frontend ─────────────────────────────────────── */

const state = {
    players: [],
    selectedPlayer: null,
    playerSource: null,
    items: [],
    pals: [],
    palDb: {},
    activeSkills: {},
    passiveSkills: {},
    selectedItem: null,
    selectedPal: null,
    waypoints: [],
    selectedWaypoint: null,
    commandLog: [],
    refreshTimer: 15,
    activeTab: 'players',
    logExpanded: true,
    itemFilterGroup: '',
    palFilterElements: [],
    palFilterBoss: false,
    palFilterWorks: [],
    palFilterRarity: '',
    palFilterSize: '',
    palFilterPS: '',
    palSortAsc: true,
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

/* Element colours (fallback if not loaded from palDb) */
const ELEM_COLORS = {
    Fire: '#F87171', Water: '#60A5FA', Ice: '#67E8F9', Electricity: '#FBBF24',
    Earth: '#A78BFA', Dark: '#818CF8', Dragon: '#C084FC', Leaf: '#34D399', Normal: '#9CA3AF',
};

/* Element SVG icons (16x16 viewBox, uses currentColor) */
const ELEM_ICONS = {
    Fire: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1c0 3.5-4 5.5-4 8.5a4 4 0 008 0C12 6.5 8 4.5 8 1z"/></svg>',
    Water: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1.5L4.5 8a3.5 3.5 0 007 0L8 1.5z"/></svg>',
    Ice: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M7.25 1h1.5v3.4l2.4-2.4 1.1 1.1L9.4 6h3.1v1.5H9.4l2.85 2.9-1.1 1.1-2.4-2.4V14h-1.5V9.1L4.85 11.5l-1.1-1.1L6.6 7.5H3.5V6h3.1L3.75 3.1l1.1-1.1 2.4 2.4V1z"/></svg>',
    Electricity: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M9.5 1L4 8.5h4L6.5 15 12 7.5H8L9.5 1z"/></svg>',
    Earth: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1a7 7 0 100 14A7 7 0 008 1zM5 5.5a1.5 1.5 0 113 0 1.5 1.5 0 01-3 0zM4 10a1 1 0 112 0 1 1 0 01-2 0zm5-1a2 2 0 114 0 2 2 0 01-4 0z"/></svg>',
    Dark: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M6 1a7 7 0 109 6.5A5.5 5.5 0 016 1z"/></svg>',
    Dragon: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1L6 5l-4 1 3 3-.5 4L8 11l3.5 2L11 9l3-3-4-1L8 1z"/></svg>',
    Leaf: '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M3 13C3 7 7 2 13 2c0 6-4 11-10 11zm1.5-1.5C7 10 9 7.5 10 4.5"/><path fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" d="M4.5 11.5C7 10 9 7.5 10 4.5"/></svg>',
    Normal: '<svg viewBox="0 0 16 16"><circle fill="currentColor" cx="8" cy="8" r="5.5"/><circle fill="var(--bg, #1a1a2e)" cx="8" cy="8" r="3"/></svg>',
};

/* Item group display labels */
const ITEM_GROUPS = ['Weapon','Body','Head','Accessory','Food','Common','Shield','Glider','SphereModule','KeyItem'];

/* Element filter list */
const PAL_ELEMENTS = ['Fire','Water','Ice','Electricity','Earth','Dark','Dragon','Leaf','Normal'];

/* Work suitability types (localised names, ordered) */
const PAL_WORK_TYPES = [
    'Kindling','Watering','Planting','Generating Electricity','Handiwork',
    'Gathering','Lumbering','Mining','Medicine Production','Cooling',
    'Transporting','Farming','Crude Oil Extraction'
];

const WORK_COLORS = {
    'Kindling': '#F87171', 'Watering': '#60A5FA', 'Planting': '#34D399',
    'Generating Electricity': '#FBBF24', 'Handiwork': '#FB923C', 'Gathering': '#A78BFA',
    'Lumbering': '#8B5CF6', 'Mining': '#94A3B8', 'Medicine Production': '#F472B6',
    'Cooling': '#67E8F9', 'Transporting': '#60A5FA', 'Farming': '#34D399',
    'Crude Oil Extraction': '#78716C'
};

const WORK_SHORT = {
    'Kindling': 'Kind', 'Watering': 'Water', 'Planting': 'Plant',
    'Generating Electricity': 'Elec', 'Handiwork': 'Hand', 'Gathering': 'Gath',
    'Lumbering': 'Lumb', 'Mining': 'Mine', 'Medicine Production': 'Med',
    'Cooling': 'Cool', 'Transporting': 'Trans', 'Farming': 'Farm',
    'Crude Oil Extraction': 'Oil'
};

/* Work suitability SVG icons (16x16 viewBox, uses currentColor) */
const WORK_ICONS = {
    'Kindling': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1c0 3.5-4 5.5-4 8.5a4 4 0 008 0C12 6.5 8 4.5 8 1z"/></svg>',
    'Watering': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1.5L4.5 8a3.5 3.5 0 007 0L8 1.5z"/></svg>',
    'Planting': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M7 14v-4C4.5 10 2 8 2 5c3 0 5 2 5 5V6c0-3 2-5 5-5 0 3-2.5 5-5 5v4c0 2-1 4-1 4H7z"/></svg>',
    'Generating Electricity': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M9.5 1L4 8.5h4L6.5 15 12 7.5H8L9.5 1z"/></svg>',
    'Handiwork': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M14 4.5a3.5 3.5 0 00-5-3.2l-1 3.2L4.2 8.2l-2.5-1L.5 9l6 6 1.8-1.2-1-2.5 3.7-3.8 3.2-1A3.5 3.5 0 0014 4.5zM2 14.5a1 1 0 110-2 1 1 0 010 2z"/></svg>',
    'Gathering': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M4 6.5L2.5 13c-.2.8.4 1.5 1.2 1.5h8.6c.8 0 1.4-.7 1.2-1.5L12 6.5H4zm4-5L5.5 5h5L8 1.5z"/></svg>',
    'Lumbering': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M9.5 2L3 8.5l1.5 1.5 2-2v6h2v-6l2 2L12 8.5 9.5 2zM4 12l-2.5 3h3L4 12z"/></svg>',
    'Mining': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M12.8 1.2a1 1 0 00-1.4 0L7 5.6 5.4 4 4 5.4 5.6 7l-4.4 4.4a1 1 0 000 1.4l2 2a1 1 0 001.4 0L9 10.4l1.6 1.6 1.4-1.4L10.4 9l4.4-4.4a1 1 0 000-1.4l-2-2z"/></svg>',
    'Medicine Production': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M6 1.5h4v4h4v4h-4v4H6v-4H2v-4h4v-4z"/></svg>',
    'Cooling': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M7.25 1h1.5v3.4l2.4-2.4 1.1 1.1L9.4 6h3.1v1.5H9.4l2.85 2.9-1.1 1.1-2.4-2.4V14h-1.5v-4.9L4.85 11.5l-1.1-1.1L6.6 7.5H3.5V6h3.1L3.75 3.1l1.1-1.1 2.4 2.4V1z"/></svg>',
    'Transporting': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M1 3.5h8v7H1v-7zm8 1h2.5l2.5 3v3h-5v-6zM4 13a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm7 0a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"/></svg>',
    'Farming': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8.5 14V9.5C10 9 12 7 12 4.5c-2 0-3.5 1.5-3.5 3.5V4C8.5 2 7 .5 5 .5 5 2.5 6.5 4 8.5 4v10h-1V14h2zM3 12h10v1.5H3V12z"/></svg>',
    'Crude Oil Extraction': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1L5 7.5a3 3 0 006 0L8 1zM4 12h8a1 1 0 011 1v1a1 1 0 01-1 1H4a1 1 0 01-1-1v-1a1 1 0 011-1z"/></svg>',
};

/* Partner skill type SVG icons (32x32 viewBox) — categorised by description keywords */
const PS_ICONS = {
    // Flying mount — spread wings
    fly: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M16 10l-6-6c-3-2-7-1-8 2 0 2 1 4 3 5l7 4h8l7-4c2-1 3-3 3-5-1-3-5-4-8-2l-6 6z"/><path fill="currentColor" d="M14 16h4v4l-2 6-2-6v-4z" opacity="0.5"/></svg>',
    // Ground mount — saddle
    ride: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M8 20c0-5 3.5-9 8-9s8 4 8 9" stroke="currentColor" stroke-width="1" fill="none"/><ellipse fill="currentColor" cx="16" cy="13" rx="5" ry="3"/><path fill="currentColor" d="M11 13c-2 0-4 1-4 3v2h2v-2c0-.5.5-1 1.5-1h1v-2zm10 0c2 0 4 1 4 3v2h-2v-2c0-.5-.5-1-1.5-1h-1v-2z" opacity="0.6"/><path fill="currentColor" d="M8 20h16v2a2 2 0 01-2 2H10a2 2 0 01-2-2v-2z" opacity="0.4"/></svg>',
    // Water mount — waves
    swim: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M4 18c2-2 4-2 6 0s4 2 6 0 4-2 6 0 4 2 6 0" stroke="currentColor" stroke-width="2.5" fill="none" stroke-linecap="round"/><path fill="currentColor" d="M6 23c2-2 4-2 6 0s4 2 6 0 4-2 6 0" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.4"/><path fill="currentColor" d="M16 6l-3 5h2v4h2v-4h2l-3-5z"/></svg>',
    // Combat follower — crossed swords
    combat: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M8 4l2 12 3-3 4 5 2-2-4-5 3-3L8 4zm16 0L12 8l3 3-4 5 2 2 4-5 3 3 2-12z" opacity="0.9"/><path fill="currentColor" d="M9 24l3-3 2 2-3 3a1.5 1.5 0 01-2-2zm14 0l-3-3-2 2 3 3a1.5 1.5 0 002-2z" opacity="0.6"/></svg>',
    // Shield — shield shape
    shield: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M16 3L5 8v8c0 7 5 11 11 14 6-3 11-7 11-14V8L16 3z" opacity="0.3"/><path fill="currentColor" d="M16 5L7 9v7c0 6 4 9.5 9 12 5-2.5 9-6 9-12V9L16 5z" fill="none" stroke="currentColor" stroke-width="1.5"/><path fill="currentColor" d="M14 13h4v2h2v4h-2v2h-4v-2h-2v-4h2v-2z" opacity="0.7"/></svg>',
    // Healer — heart with plus
    heal: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M16 28l-1.5-1.4C7 20 3 16 3 11.5 3 7.4 6 4 10 4c2.3 0 4.5 1.1 6 2.8C17.5 5.1 19.7 4 22 4c4 0 7 3.4 7 7.5 0 4.5-4 8.5-11.5 15.1L16 28z" opacity="0.8"/><path fill="currentColor" d="M14.5 12h3v3h3v3h-3v3h-3v-3h-3v-3h3v-3z" fill="white" opacity="0.9"/></svg>',
    // Ranch producer — egg/barn
    ranch: '<svg viewBox="0 0 32 32"><ellipse fill="currentColor" cx="16" cy="18" rx="7" ry="9" opacity="0.7"/><ellipse fill="currentColor" cx="16" cy="15" rx="4" ry="5" opacity="0.15"/><path fill="currentColor" d="M6 27h20v2H6z" opacity="0.3"/></svg>',
    // Carry supplies — backpack
    carry: '<svg viewBox="0 0 32 32"><rect fill="currentColor" x="9" y="10" width="14" height="16" rx="3" opacity="0.7"/><path fill="currentColor" d="M12 10V8a4 4 0 018 0v2" stroke="currentColor" stroke-width="2" fill="none"/><rect fill="currentColor" x="12" y="16" width="8" height="5" rx="1" opacity="0.25"/></svg>',
    // Movement speed — running wind
    speed: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M18 6a5 5 0 015 5h-3a2 2 0 10-2-2V6zm2 10a4 4 0 014 4h-3a1 1 0 10-1-1v-3z" opacity="0.5"/><path fill="currentColor" d="M4 13h14M4 19h10M4 25h7" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" opacity="0.7"/></svg>',
    // Sanity — moon calm
    sanity: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M14 4a12 12 0 100 24c-5 0-8-5-8-12S9 4 14 4z"/><circle fill="currentColor" cx="22" cy="8" r="1" opacity="0.5"/><circle fill="currentColor" cx="25" cy="12" r="0.7" opacity="0.4"/><circle fill="currentColor" cx="20" cy="5" r="0.7" opacity="0.3"/></svg>',
    // Passive buff — star arrow up
    buff: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M16 3l3.5 7 7.5 1.1-5.4 5.3L23 24l-7-3.7L9 24l1.4-7.6L5 11.1l7.5-1.1L16 3z" opacity="0.8"/></svg>',
    // Gun/ranged — crosshair
    gun: '<svg viewBox="0 0 32 32"><circle fill="none" stroke="currentColor" stroke-width="2" cx="16" cy="16" r="8"/><circle fill="currentColor" cx="16" cy="16" r="2"/><path stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M16 4v6m0 12v6M4 16h6m12 0h6"/></svg>',
    // Thief/stealer — grabbing hand
    thief: '<svg viewBox="0 0 32 32"><path fill="currentColor" d="M12 14v-4a1.5 1.5 0 013 0v4m0-5v-3a1.5 1.5 0 013 0v3m0 4v-6a1.5 1.5 0 013 0v6m0 0a1.5 1.5 0 013 0v3c0 5-3 9-8 9h-1c-4 0-7-3-7-7v-3a1.5 1.5 0 013 0v2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};

function getPartnerSkillType(desc) {
    if (!desc) return 'combat';
    var d = desc.toLowerCase();
    if (d.includes('flying mount')) return 'fly';
    if (d.includes('travel on water')) return 'swim';
    if (d.includes('can be ridden')) return 'ride';
    if (d.includes('becomes a shield')) return 'shield';
    if (d.includes('heals the player') || d.includes('continuously heals')) return 'heal';
    if (d.includes('ranch') || d.includes('sometimes drops')) return 'ranch';
    if (d.includes('carry supplies') || d.includes('carrying capacity')) return 'carry';
    if (d.includes('movement speed')) return 'speed';
    if (d.includes('sanity decline')) return 'sanity';
    if (d.includes('fires') && d.includes('rifle')) return 'gun';
    if (d.includes('steals items')) return 'thief';
    if (d.includes('increases') && d.includes('attack power')) return 'buff';
    if (d.includes('attacks nearby') || d.includes('follows the player')) return 'combat';
    return 'buff';
}

/* Partner skill type labels and colours for filter pills */
const PS_TYPE_META = {
    fly:    { label: 'Fly Mount',   color: '#67E8F9' },
    ride:   { label: 'Ride',        color: '#FBBF24' },
    swim:   { label: 'Swim',        color: '#60A5FA' },
    combat: { label: 'Combat',      color: '#F87171' },
    shield: { label: 'Shield',      color: '#94A3B8' },
    heal:   { label: 'Heal',        color: '#F472B6' },
    ranch:  { label: 'Ranch',       color: '#FB923C' },
    carry:  { label: 'Carry',       color: '#A78BFA' },
    speed:  { label: 'Speed',       color: '#34D399' },
    sanity: { label: 'Sanity',      color: '#818CF8' },
    buff:   { label: 'Buff',        color: '#FBBF24' },
    gun:    { label: 'Ranged',      color: '#EF4444' },
    thief:  { label: 'Thief',       color: '#C084FC' },
};
const PS_TYPE_ORDER = ['fly','ride','swim','combat','shield','heal','ranch','carry','speed','sanity','buff','gun','thief'];

/* Stat maximums for bar normalisation (will be computed from palDb) */
let palStatMax = { hp: 100, attack: 100, defense: 100, stamina: 100 };

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

/* ── Rarity helpers ─────────────────────────────────────────────────────────── */

const RARITY_NAMES = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Legendary'];

function rarityName(r) { return RARITY_NAMES[Math.min(r || 0, 5)]; }

function rarityDots(r) {
    if (r == null || r === 0) return '';
    const n = Math.min(r, 5);
    let html = '<span class="rarity-dots">';
    for (let i = 0; i < n; i++) {
        html += '<span class="rarity-dot rarity-' + Math.min(r, 5) + '"></span>';
    }
    return html + '</span>';
}

function iconImg(iconName, size) {
    if (!iconName) {
        const s = size || 32;
        return '<span class="icon-placeholder' + (s > 40 ? '-lg' : '') + '">?</span>';
    }
    const cls = size && size > 40 ? 'icon-thumb-lg' : 'icon-thumb';
    return '<img class="' + cls + '" src="/api/icon/' + encodeURIComponent(iconName) + '" ' +
        'onerror="this.outerHTML=\'<span class=\\\'icon-placeholder' + (size > 40 ? '-lg' : '') + '\\\'>?</span>\'" loading="lazy">';
}

function palBodyImg(imageName) {
    if (!imageName) return '';
    return '<img class="pal-portrait" src="/api/pal-image/' + encodeURIComponent(imageName) + '" ' +
        'onerror="this.outerHTML=\'\'" loading="lazy">';
}

/* ── Items ──────────────────────────────────────────────────────────────────── */

let itemSortMode = 'default';

function renderItemFilters() {
    const el = document.getElementById('item-filters');
    if (!el) return;
    // Count items per group
    const counts = {};
    for (const item of state.items) {
        const g = item.group || 'Unknown';
        counts[g] = (counts[g] || 0) + 1;
    }
    let html = '<button class="filter-pill' + (state.itemFilterGroup === '' ? ' active' : '') +
        '" onclick="setItemFilter(\'\')" data-group="">All <span class="pill-count">' + state.items.length + '</span></button>';
    for (const g of ITEM_GROUPS) {
        if (!counts[g]) continue;
        const active = state.itemFilterGroup === g ? ' active' : '';
        html += '<button class="filter-pill' + active +
            '" onclick="setItemFilter(\'' + g + '\')" data-group="' + g + '">' +
            esc(g) + ' <span class="pill-count">' + counts[g] + '</span></button>';
    }
    el.innerHTML = html;
}

function setItemFilter(group) {
    state.itemFilterGroup = group;
    renderItemFilters();
    renderItems(document.getElementById('give-search').value);
}

function renderPalFilters() {
    const el = document.getElementById('pal-filters');
    if (!el) return;
    // Count pals per element from palDb
    const elemCounts = {};
    let bossCount = 0;
    for (const p of state.pals) {
        const db = state.palDb[p.id];
        if (p.is_boss) bossCount++;
        if (db && db.elements) {
            for (const e of db.elements) {
                elemCounts[e.id] = (elemCounts[e.id] || 0) + 1;
            }
        }
    }
    const noElem = state.palFilterElements.length === 0;
    let html = '<button class="filter-pill' + (noElem ? ' active' : '') +
        '" onclick="clearPalElemFilter()">All</button>';
    for (const e of PAL_ELEMENTS) {
        if (!elemCounts[e]) continue;
        const color = ELEM_COLORS[e] || '#888';
        const active = state.palFilterElements.includes(e);
        const cls = active ? ' elem-active' : '';
        const style = active
            ? ' style="--pill-color:' + color + ';--pill-color-dim:' + color + '15"'
            : ' style="--pill-color:' + color + '"';
        const icon = ELEM_ICONS[e] || '';
        html += '<button class="filter-pill elem-pill' + cls + '"' + style +
            ' onclick="togglePalElemFilter(\'' + e + '\')" data-elem="' + e + '">' +
            '<span class="elem-pill-icon" style="color:' + color + '">' + icon + '</span>' +
            esc(e) + ' <span class="pill-count">' + elemCounts[e] + '</span></button>';
    }
    // Boss toggle
    html += '<button class="filter-toggle' + (state.palFilterBoss ? ' active' : '') +
        '" onclick="toggleBossFilter()">Boss ' + (bossCount > 0 ? '<span class="pill-count">' + bossCount + '</span>' : '') + '</button>';
    el.innerHTML = html;
}

function togglePalElemFilter(elem) {
    const idx = state.palFilterElements.indexOf(elem);
    if (idx >= 0) state.palFilterElements.splice(idx, 1);
    else state.palFilterElements.push(elem);
    renderPalFilters();
    renderPals(document.getElementById('spawn-search').value);
}
function clearPalElemFilter() {
    state.palFilterElements = [];
    renderPalFilters();
    renderPals(document.getElementById('spawn-search').value);
}

function toggleBossFilter() {
    state.palFilterBoss = !state.palFilterBoss;
    renderPalFilters();
    renderPals(document.getElementById('spawn-search').value);
}

function renderPalWorkFilters() {
    const el = document.getElementById('pal-work-filters');
    if (!el) return;
    // Count pals per work type from palDb
    const workCounts = {};
    for (const p of state.pals) {
        const db = state.palDb[p.id];
        if (db && db.work) {
            for (const wName of Object.keys(db.work)) {
                workCounts[wName] = (workCounts[wName] || 0) + 1;
            }
        }
    }
    const noWork = state.palFilterWorks.length === 0;
    let html = '<button class="filter-pill' + (noWork ? ' active' : '') +
        '" onclick="clearPalWorkFilter()">All Work</button>';
    for (const w of PAL_WORK_TYPES) {
        if (!workCounts[w]) continue;
        const color = WORK_COLORS[w] || '#888';
        const active = state.palFilterWorks.includes(w);
        const cls = active ? ' elem-active' : '';
        const style = active
            ? ' style="--pill-color:' + color + ';--pill-color-dim:' + color + '15"'
            : ' style="--pill-color:' + color + '"';
        const icon = WORK_ICONS[w] || '';
        const short = WORK_SHORT[w] || w;
        html += '<button class="filter-pill work-pill' + cls + '"' + style +
            ' onclick="togglePalWorkFilter(\'' + esc(w) + '\')" data-work="' + esc(w) + '">' +
            '<span class="work-pill-icon" style="color:' + color + '">' + icon + '</span>' +
            esc(short) + ' <span class="pill-count">' + workCounts[w] + '</span></button>';
    }
    el.innerHTML = html;
}

function togglePalWorkFilter(work) {
    const idx = state.palFilterWorks.indexOf(work);
    if (idx >= 0) state.palFilterWorks.splice(idx, 1);
    else state.palFilterWorks.push(work);
    renderPalWorkFilters();
    renderPals(document.getElementById('spawn-search').value);
}
function clearPalWorkFilter() {
    state.palFilterWorks = [];
    renderPalWorkFilters();
    renderPals(document.getElementById('spawn-search').value);
}

function renderPalPSFilters() {
    const el = document.getElementById('pal-ps-filters');
    if (!el) return;
    // Count pals per partner skill type
    const psCounts = {};
    for (const p of state.pals) {
        const db = state.palDb[p.id];
        if (db && db.partner_skill_desc) {
            const t = getPartnerSkillType(db.partner_skill_desc);
            psCounts[t] = (psCounts[t] || 0) + 1;
        }
    }
    let html = '<button class="filter-pill' + (state.palFilterPS === '' ? ' active' : '') +
        '" onclick="setPalPSFilter(\'\')">All Skills</button>';
    for (const t of PS_TYPE_ORDER) {
        if (!psCounts[t]) continue;
        const meta = PS_TYPE_META[t];
        const active = state.palFilterPS === t;
        const cls = active ? ' elem-active' : '';
        const style = active
            ? ' style="--pill-color:' + meta.color + ';--pill-color-dim:' + meta.color + '15"'
            : ' style="--pill-color:' + meta.color + '"';
        const icon = PS_ICONS[t] || '';
        html += '<button class="filter-pill ps-pill' + cls + '"' + style +
            ' onclick="setPalPSFilter(\'' + t + '\')">' +
            '<span class="ps-pill-icon" style="color:' + meta.color + '">' + icon + '</span>' +
            meta.label + ' <span class="pill-count">' + psCounts[t] + '</span></button>';
    }
    el.innerHTML = html;
}

function setPalPSFilter(type) {
    state.palFilterPS = type;
    renderPalPSFilters();
    renderPals(document.getElementById('spawn-search').value);
}

async function loadItems() {
    const data = await apiGet('/api/items');
    if (!data) return;
    state.items = Array.isArray(data) ? data : [];
    renderItemFilters();
    renderItems();
    document.getElementById('btn-give').disabled = false;
    document.getElementById('item-count').textContent = state.items.length;
}

function sortItems(items) {
    const sorted = [...items];
    switch (itemSortMode) {
        case 'name':   return sorted.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
        case 'rarity': return sorted.sort((a, b) => (b.rarity || 0) - (a.rarity || 0));
        case 'price':  return sorted.sort((a, b) => (b.price || 0) - (a.price || 0));
        case 'weight': return sorted.sort((a, b) => (b.weight || 0) - (a.weight || 0));
        default:       return sorted;
    }
}

function renderItems(filter) {
    const el = document.getElementById('item-list');
    let items = state.items;

    // Apply group filter
    if (state.itemFilterGroup) {
        items = items.filter(i => i.group === state.itemFilterGroup);
    }

    if (filter) {
        const lf = filter.toLowerCase();
        items = items.filter(i =>
            i.name.toLowerCase().includes(lf) ||
            i.id.toLowerCase().includes(lf) ||
            (i.group && i.group.toLowerCase().includes(lf))
        );
    }

    items = sortItems(items);

    if (items.length === 0) {
        el.innerHTML = '<div class="empty-state">No items found</div>';
        return;
    }

    const shown = items.slice(0, 200);
    el.innerHTML = shown.map(i => {
        const sel = i.id === (state.selectedItem && state.selectedItem.id) ? ' selected' : '';
        const group = i.group ? '<span class="item-group">' + esc(i.group) + '</span>' : '';
        const dots = rarityDots(i.rarity);

        return '<div class="list-item-icon' + sel + '" onclick="selectItem(\'' + esc(i.id) + '\')">' +
            iconImg(i.icon) +
            '<div class="list-item-info">' +
                '<div class="list-item-top">' +
                    '<span class="item-name">' + esc(i.name) + '</span>' +
                    dots +
                    group +
                '</div>' +
                '<div class="list-item-bottom">' + esc(i.id) + '</div>' +
            '</div>' +
        '</div>';
    }).join('');

    if (items.length > 200) {
        el.innerHTML += '<div class="empty-state">' + (items.length - 200) + ' more — refine search</div>';
    }
}

function formatDuration(seconds) {
    if (!seconds) return '—';
    if (seconds >= 3600) return Math.floor(seconds / 3600) + 'h ' + Math.floor((seconds % 3600) / 60) + 'min';
    if (seconds >= 60) return Math.floor(seconds / 60) + ' min';
    return seconds + 's';
}

function renderItemDetail() {
    const el = document.getElementById('item-detail');
    const item = state.selectedItem;
    if (!item) {
        el.innerHTML = '<div class="empty-state">Select an item from the list</div>';
        return;
    }

    const rarityClass = 'rarity-label-' + Math.min(item.rarity || 0, 5);
    const desc = item.description
        ? '<div class="detail-desc">' + esc(item.description) + '</div>'
        : '';

    // Type badges
    let typeBadgesHtml = '';
    if (item.type_a || item.type_b) {
        typeBadgesHtml = '<div class="type-badges">';
        if (item.type_a) typeBadgesHtml += '<span class="type-badge">' + esc(item.type_a) + '</span>';
        if (item.type_b && item.type_b !== item.type_a) typeBadgesHtml += '<span class="type-badge">' + esc(item.type_b) + '</span>';
        typeBadgesHtml += '</div>';
    }

    // Core stats
    let statsHtml = '<div class="detail-section-label">Stats</div><div class="detail-stats">' +
        statItem('Group', item.group || '—') +
        statItem('Rarity', rarityName(item.rarity)) +
        statItem('Weight', item.weight != null ? item.weight : '—') +
        statItem('Price', item.price != null ? item.price.toLocaleString() : '—') +
        statItem('Rank', item.rank != null ? item.rank : '—') +
        statItem('Max Stack', item.max_stack || '—');

    // Combat stats
    if (item.damage != null) statsHtml += statItem('Damage', item.damage);
    if (item.defense != null) statsHtml += statItem('Defence', item.defense);
    if (item.dynamic) {
        if (item.dynamic.durability != null) statsHtml += statItem('Durability', item.dynamic.durability.toLocaleString());
        if (item.dynamic.magazine_size != null) statsHtml += statItem('Magazine', item.dynamic.magazine_size);
    }
    statsHtml += '</div>';

    // Food effects section
    let effectHtml = '';
    if (item.effect) {
        effectHtml = '<div class="detail-section-label">Food Effects</div>';
        effectHtml += '<div class="buff-duration">Duration: ' + formatDuration(item.effect.duration) + '</div>';
        if (item.effect.modifiers && item.effect.modifiers.length > 0) {
            effectHtml += '<div class="buff-cards">';
            for (const mod of item.effect.modifiers) {
                const sign = mod.value >= 0 ? '+' : '';
                effectHtml += '<span class="buff-chip">' + sign + mod.value + ' ' + esc(mod.type) + '</span>';
            }
            effectHtml += '</div>';
        }
        if (item.corruption_factor != null) {
            effectHtml += '<div style="margin-top:6px">' + statItem('Spoilage Rate', (item.corruption_factor * 100).toFixed(2) + '%') + '</div>';
        }
    }

    // Passive skills section (for weapons/armour)
    let passiveHtml = '';
    const passiveArr = item.dynamic && item.dynamic.passive_skills
        ? (Array.isArray(item.dynamic.passive_skills) ? item.dynamic.passive_skills : [item.dynamic.passive_skills])
        : [];
    if (passiveArr.length > 0) {
        passiveHtml = '<div class="detail-section-label">Passive Skills</div><div class="passive-list">';
        for (const sid of passiveArr) {
            const ps = state.passiveSkills[sid];
            const name = ps ? ps.name : sid;
            const desc = ps && ps.description ? ps.description : '';
            passiveHtml += '<div class="passive-item">' +
                '<div class="passive-item-name">' + esc(name) + '</div>' +
                (desc ? '<div class="passive-item-desc">' + esc(desc) + '</div>' : '') +
            '</div>';
        }
        passiveHtml += '</div>';
    }

    el.innerHTML =
        '<div class="detail-header">' +
            iconImg(item.icon, 80) +
            '<div class="detail-header-info">' +
                '<div class="detail-name">' + esc(item.name) + '</div>' +
                '<div class="detail-id">' + esc(item.id) + '</div>' +
                '<div style="margin-top:2px">' +
                    '<span class="' + rarityClass + '" style="font-size:11px;font-weight:600">' + rarityName(item.rarity) + '</span>' +
                    rarityDots(item.rarity) +
                '</div>' +
                typeBadgesHtml +
            '</div>' +
        '</div>' +
        desc +
        statsHtml +
        effectHtml +
        passiveHtml;
}

function statItem(label, value) {
    return '<div class="stat-item">' +
        '<span class="stat-label">' + label + '</span>' +
        '<span class="stat-value">' + value + '</span>' +
    '</div>';
}

function selectItem(id) {
    state.selectedItem = state.items.find(i => i.id === id) || null;
    renderItems(document.getElementById('give-search').value);
    renderItemDetail();
}

/* ── Pals ───────────────────────────────────────────────────────────────────── */

let palSortMode = 'name';

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
    // Compute stat maximums for bar normalisation
    let maxHp = 0, maxAtk = 0, maxDef = 0, maxSta = 0;
    for (const p of data) {
        if (p.hp > maxHp) maxHp = p.hp;
        if (p.attack > maxAtk) maxAtk = p.attack;
        if (p.defense > maxDef) maxDef = p.defense;
        if (p.stamina > maxSta) maxSta = p.stamina;
    }
    palStatMax = { hp: maxHp || 100, attack: maxAtk || 100, defense: maxDef || 100, stamina: maxSta || 100 };

    document.getElementById('pal-count').textContent = data.length;
    renderPalFilters();
    renderPalWorkFilters();
    renderPalPSFilters();
    if (state.pals.length > 0) renderPals();
}

async function loadActiveSkills() {
    const data = await apiGet('/api/active-skills');
    if (!data || !Array.isArray(data)) return;
    state.activeSkills = {};
    for (const s of data) {
        state.activeSkills[s.id] = s;
    }
}

async function loadPassiveSkills() {
    const data = await apiGet('/api/passive-skills');
    if (!data || !Array.isArray(data)) return;
    state.passiveSkills = {};
    for (const s of data) {
        state.passiveSkills[s.id] = s;
    }
}

function sortPals(pals) {
    const sorted = [...pals];
    const db = state.palDb;
    switch (palSortMode) {
        case 'name':
            sorted.sort((a, b) => {
                const na = (db[a.id] && db[a.id].name) || a.name || '';
                const nb = (db[b.id] && db[b.id].name) || b.name || '';
                return na.localeCompare(nb);
            });
            break;
        case 'paldeck':
            sorted.sort((a, b) => {
                const da = (db[a.id] && db[a.id].pal_deck_index) || 9999;
                const dbb = (db[b.id] && db[b.id].pal_deck_index) || 9999;
                return da - dbb;
            });
            break;
        case 'rarity':
            sorted.sort((a, b) => {
                const ra = (db[a.id] && db[a.id].rarity) || 0;
                const rb = (db[b.id] && db[b.id].rarity) || 0;
                return rb - ra;
            });
            break;
        case 'hp':
            sorted.sort((a, b) => ((db[b.id] && db[b.id].hp) || 0) - ((db[a.id] && db[a.id].hp) || 0));
            break;
        case 'attack':
            sorted.sort((a, b) => ((db[b.id] && db[b.id].attack) || 0) - ((db[a.id] && db[a.id].attack) || 0));
            break;
        case 'defense':
            sorted.sort((a, b) => ((db[b.id] && db[b.id].defense) || 0) - ((db[a.id] && db[a.id].defense) || 0));
            break;
    }
    if (!state.palSortAsc) sorted.reverse();
    return sorted;
}

function renderPals(filter) {
    const el = document.getElementById('pal-list');
    let pals = state.pals;

    // Apply element filter (multi-select — pal must have ALL selected elements)
    if (state.palFilterElements.length > 0) {
        pals = pals.filter(p => {
            const db = state.palDb[p.id];
            if (!db || !db.elements) return false;
            const palElems = db.elements.map(e => e.id);
            return state.palFilterElements.every(f => palElems.includes(f));
        });
    }

    // Apply boss filter
    if (state.palFilterBoss) {
        pals = pals.filter(p => p.is_boss);
    }

    // Apply work suitability filter (multi-select — pal must have ALL selected work types)
    if (state.palFilterWorks.length > 0) {
        pals = pals.filter(p => {
            const db = state.palDb[p.id];
            if (!db || !db.work) return false;
            return state.palFilterWorks.every(f => db.work[f] > 0);
        });
    }

    // Apply rarity filter
    if (state.palFilterRarity) {
        const rVal = parseInt(state.palFilterRarity);
        pals = pals.filter(p => {
            const db = state.palDb[p.id];
            return db && db.rarity === rVal;
        });
    }

    // Apply size filter
    if (state.palFilterSize) {
        pals = pals.filter(p => {
            const db = state.palDb[p.id];
            return db && db.size === state.palFilterSize;
        });
    }

    // Apply partner skill type filter
    if (state.palFilterPS) {
        pals = pals.filter(p => {
            const db = state.palDb[p.id];
            if (!db || !db.partner_skill_desc) return false;
            return getPartnerSkillType(db.partner_skill_desc) === state.palFilterPS;
        });
    }

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

    pals = sortPals(pals);

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
                '<span class="element-badge" style="background:' + e.color + '33;color:' + e.color + '"><span class="elem-icon">' + (ELEM_ICONS[e.id || e.name] || '') + '</span>' + esc(e.name) + '</span>'
            ).join(' ');
            const dots = rarityDots(db.rarity);
            const deckIdx = db.pal_deck_index ? '<span class="list-item-bottom">#' + db.pal_deck_index + '</span>' : '';

            // Mini work icons for list
            let miniWork = '';
            if (db.work) {
                const wEntries = Object.entries(db.work).sort((a, b) => b[1] - a[1]);
                miniWork = wEntries.map(([wn, wl]) => {
                    const wc = WORK_COLORS[wn] || '#888';
                    const wi = WORK_ICONS[wn] || '';
                    return '<span class="mini-work" title="' + esc(wn) + '" style="color:' + wc + '">' +
                        '<span class="mini-work-icon">' + wi + '</span>' +
                        '<span class="mini-work-lvl">x' + wl + '</span></span>';
                }).join('');
            }

            return '<div class="pal-item-rich' + sel + '" onclick="selectPal(\'' + esc(p.id) + '\')">' +
                iconImg(db.icon, 40) +
                '<div class="pal-item-rich-info">' +
                    '<div class="pal-item-top">' +
                        '<span class="item-name">' + esc(db.name) + '</span>' +
                        dots +
                        boss +
                        elemHtml +
                    '</div>' +
                    '<div class="list-item-bottom">' +
                        (db.pal_deck_index ? '#' + db.pal_deck_index : '') +
                        (db.size ? '<span class="mini-size size-' + db.size.toLowerCase() + '">' + esc(db.size) + '</span>' : '') +
                        miniWork +
                    '</div>' +
                '</div>' +
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
        el.innerHTML += '<div class="empty-state">' + (pals.length - 200) + ' more — refine search</div>';
    }
}

function statBarRow(label, value, max, cls) {
    const pct = max > 0 ? Math.min((value / max) * 100, 100) : 0;
    return '<div class="stat-bar-row">' +
        '<span class="stat-bar-label">' + label + '</span>' +
        '<div class="stat-bar-bg"><div class="stat-bar-fill ' + cls + '" style="width:' + pct.toFixed(1) + '%"></div></div>' +
        '<span class="stat-bar-val">' + (value != null ? value : '—') + '</span>' +
    '</div>';
}

function renderPalDetail() {
    const el = document.getElementById('pal-detail');
    const pal = state.selectedPal;
    if (!pal) {
        el.innerHTML = '<div class="empty-state">Select a pal from the list</div>';
        return;
    }

    const db = state.palDb[pal.id];
    if (!db) {
        el.innerHTML = '<div class="detail-header">' +
            '<span class="icon-placeholder-lg">?</span>' +
            '<div class="detail-header-info">' +
                '<div class="detail-name">' + esc(pal.name) + '</div>' +
                '<div class="detail-id">' + esc(pal.id) + '</div>' +
            '</div>' +
        '</div>';
        return;
    }

    const rarityClass = 'rarity-label-' + Math.min(db.rarity || 0, 5);
    const desc = db.description
        ? '<div class="detail-desc">' + esc(db.description) + '</div>'
        : '';

    const elemHtml = (db.elements || []).map(e =>
        '<span class="element-badge" style="background:' + e.color + '33;color:' + e.color + '"><span class="elem-icon">' + (ELEM_ICONS[e.id || e.name] || '') + '</span>' + esc(e.name) + '</span>'
    ).join(' ');

    // Trait badges
    let traitsHtml = '<div class="trait-badges">';
    if (db.size) traitsHtml += '<span class="trait-badge size-badge">' + esc(db.size) + '</span>';
    if (db.nocturnal) traitsHtml += '<span class="trait-badge nocturnal">Nocturnal</span>';
    if (db.predator) traitsHtml += '<span class="trait-badge predator">Predator</span>';
    traitsHtml += '</div>';

    // Overview stats
    let overviewHtml = '<div class="detail-section-label">Overview</div><div class="detail-stats">' +
        statItem('Size', db.size || '—') +
        statItem('Rarity', rarityName(db.rarity)) +
        statItem('Genus', db.genus_category || '—') +
        statItem('Food', db.food_amount != null ? db.food_amount : '—') +
        statItem('Nocturnal', db.nocturnal ? 'Yes' : 'No') +
        statItem('Predator', db.predator ? 'Yes' : 'No') +
        statItem('Male %', db.male_probability != null ? db.male_probability + '%' : '—') +
        statItem('Capture Rate', db.capture_rate_correct != null ? db.capture_rate_correct.toFixed(2) + 'x' : '—') +
    '</div>';

    // Stat bars
    let statBarsHtml = '<div class="detail-section-label">Base Stats</div>' +
        statBarRow('HP', db.hp, palStatMax.hp, 'hp') +
        statBarRow('ATK', db.attack, palStatMax.attack, 'atk') +
        statBarRow('DEF', db.defense, palStatMax.defense, 'def') +
        statBarRow('STA', db.stamina, palStatMax.stamina, 'sta');

    // Movement section
    let moveHtml = '';
    if ((db.run_speed && db.run_speed > 0) || (db.ride_sprint_speed && db.ride_sprint_speed > 0)) {
        moveHtml = '<div class="detail-section-label">Movement</div><div class="detail-stats">';
        if (db.run_speed) moveHtml += statItem('Run Speed', db.run_speed);
        if (db.ride_sprint_speed) moveHtml += statItem('Ride Sprint', db.ride_sprint_speed);
        moveHtml += '</div>';
    }

    // Work suitability — compact chip row
    const workEntries = db.work ? Object.entries(db.work) : [];
    let workHtml = '';
    if (workEntries.length > 0) {
        workHtml = '<div class="detail-section-label">Work Suitability</div><div class="work-chips">';
        workEntries.sort((a, b) => b[1] - a[1]);
        for (const [name, level] of workEntries) {
            const color = WORK_COLORS[name] || '#888';
            const short = WORK_SHORT[name] || name;
            const icon = WORK_ICONS[name] || '';
            workHtml += '<span class="work-chip" style="--wc:' + color + '" title="' + esc(name) + ' Lv.' + level + '">' +
                '<span class="work-chip-icon">' + icon + '</span>' +
                '<span class="work-chip-lvl">x' + level + '</span>' +
            '</span>';
        }
        workHtml += '</div>';
    }

    // Skills table (active skills from skill_set)
    let skillsHtml = '';
    if (db.skill_set && Object.keys(db.skill_set).length > 0) {
        const entries = Object.entries(db.skill_set).sort((a, b) => a[1] - b[1]);
        skillsHtml = '<div class="detail-section-label">Learnable Skills</div>' +
            '<table class="skill-table"><thead><tr>' +
            '<th>Lv</th><th>Skill</th><th></th><th>Pow</th><th>CD</th><th>Description</th>' +
            '</tr></thead><tbody>';
        for (const [skillId, lvl] of entries) {
            const sk = state.activeSkills[skillId];
            const name = sk ? sk.name : skillId;
            const elem = sk ? sk.element : '';
            const color = ELEM_COLORS[elem] || '#888';
            const power = sk && sk.power != null ? sk.power : '—';
            const cd = sk && sk.cool_time != null ? sk.cool_time + 's' : '—';
            const sdesc = sk && sk.description ? sk.description : '';
            skillsHtml += '<tr>' +
                '<td class="skill-lvl">' + lvl + '</td>' +
                '<td class="skill-name">' + esc(name) + '</td>' +
                '<td><span class="skill-elem-dot" style="background:' + color + '" title="' + esc(elem) + '"></span></td>' +
                '<td class="skill-power">' + power + '</td>' +
                '<td class="skill-cd">' + cd + '</td>' +
                '<td class="skill-desc" title="' + esc(sdesc) + '">' + esc(sdesc) + '</td>' +
            '</tr>';
        }
        skillsHtml += '</tbody></table>';
    }

    // Breeding / capture appendix
    let appendixHtml = '<div class="appendix-section"><div class="detail-section-label">Breeding &amp; Capture</div>' +
        '<div class="detail-stats">' +
        statItem('Breed Rank', db.combi_rank != null ? db.combi_rank : '—') +
        statItem('Capture Rate', db.capture_rate_correct != null ? db.capture_rate_correct.toFixed(2) + 'x' : '—') +
        statItem('Stomach', db.max_full_stomach != null ? db.max_full_stomach : '—') +
        statItem('Stamina', db.stamina != null ? db.stamina : '—') +
        '</div></div>';

    // Full-body image (own section above header)
    let portraitSection = '';
    if (db.image) {
        portraitSection = '<div class="pal-portrait-section">' + palBodyImg(db.image) + '</div>';
    }

    // Partner skill — prominent standalone card with type-based icon
    let partnerHtml = '';
    if (db.partner_skill_name && db.partner_skill_name.length > 0) {
        const psType = getPartnerSkillType(db.partner_skill_desc);
        const psIconSvg = PS_ICONS[psType] || PS_ICONS.combat;
        partnerHtml = '<div class="partner-card ps-type-' + psType + '">' +
            '<div class="partner-card-header">' +
                '<div class="ps-icon-wrap">' + psIconSvg + '</div>' +
                '<div class="partner-card-title">' +
                    '<div class="partner-card-label">Partner Skill</div>' +
                    '<div class="partner-card-name">' + esc(db.partner_skill_name) + '</div>' +
                '</div>' +
            '</div>' +
            (db.partner_skill_desc ? '<div class="partner-card-desc">' + esc(db.partner_skill_desc) + '</div>' : '') +
        '</div>';
    }

    el.innerHTML =
        '<div class="detail-header">' +
            iconImg(db.icon, 80) +
            '<div class="detail-header-info">' +
                '<div class="detail-name">' + esc(db.name) + '</div>' +
                '<div class="detail-id">' + esc(pal.id) +
                    (db.pal_deck_index ? ' | Paldeck #' + db.pal_deck_index : '') +
                '</div>' +
                '<div style="margin-top:4px">' +
                    '<span class="' + rarityClass + '" style="font-size:11px;font-weight:600">' + rarityName(db.rarity) + '</span>' +
                    rarityDots(db.rarity) +
                '</div>' +
                (elemHtml ? '<div class="detail-elements" style="margin-top:4px">' + elemHtml + '</div>' : '') +
                traitsHtml +
            '</div>' +
        '</div>' +
        portraitSection +
        desc +
        partnerHtml +
        workHtml +
        overviewHtml +
        statBarsHtml +
        moveHtml +
        skillsHtml +
        appendixHtml;
}

function selectPal(id) {
    state.selectedPal = state.pals.find(p => p.id === id) || null;
    renderPals(document.getElementById('spawn-search').value);
    renderPalDetail();
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

/* ── Resizable Split Panes ─────────────────────────────────────────────────── */

function initResizableSplits() {
    document.querySelectorAll('.split-handle').forEach(handle => {
        handle.addEventListener('mousedown', (e) => {
            e.preventDefault();
            const parent = handle.parentElement;
            const rect = parent.getBoundingClientRect();
            const padding = parseFloat(getComputedStyle(parent).paddingLeft) || 10;
            const gap = parseFloat(getComputedStyle(parent).gap) || 10;
            const innerWidth = rect.width - padding * 2 - gap * 2 - 6;

            handle.classList.add('active');
            document.body.classList.add('resizing');

            function onMouseMove(ev) {
                const leftPx = ev.clientX - rect.left - padding - gap / 2;
                const leftPct = Math.max(0.2, Math.min(0.8, leftPx / (innerWidth + 6)));
                parent.style.gridTemplateColumns =
                    leftPct + 'fr 6px ' + (1 - leftPct) + 'fr';
            }

            function onMouseUp() {
                handle.classList.remove('active');
                document.body.classList.remove('resizing');
                document.removeEventListener('mousemove', onMouseMove);
                document.removeEventListener('mouseup', onMouseUp);
            }

            document.addEventListener('mousemove', onMouseMove);
            document.addEventListener('mouseup', onMouseUp);
        });

        handle.addEventListener('dblclick', () => {
            handle.parentElement.style.gridTemplateColumns = '1fr 6px 1fr';
        });
    });
}

/* ── Initialisation ────────────────────────────────────────────────────────── */

document.addEventListener('DOMContentLoaded', () => {
    // Search filters
    document.getElementById('give-search').addEventListener('input', (e) => renderItems(e.target.value));
    document.getElementById('spawn-search').addEventListener('input', (e) => renderPals(e.target.value));
    document.getElementById('wp-search').addEventListener('input', () => renderWaypoints());
    document.getElementById('wp-cat-filter').addEventListener('change', () => renderWaypoints());

    // Sort controls
    document.getElementById('item-sort').addEventListener('change', (e) => {
        itemSortMode = e.target.value;
        renderItems(document.getElementById('give-search').value);
    });
    document.getElementById('pal-sort').addEventListener('change', (e) => {
        palSortMode = e.target.value;
        renderPals(document.getElementById('spawn-search').value);
    });
    document.getElementById('pal-order').addEventListener('change', (e) => {
        state.palSortAsc = e.target.value === 'asc';
        renderPals(document.getElementById('spawn-search').value);
    });
    document.getElementById('pal-rarity-filter').addEventListener('change', (e) => {
        state.palFilterRarity = e.target.value;
        renderPals(document.getElementById('spawn-search').value);
    });
    document.getElementById('pal-size-filter').addEventListener('change', (e) => {
        state.palFilterSize = e.target.value;
        renderPals(document.getElementById('spawn-search').value);
    });

    // Resizable split panes
    initResizableSplits();

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
    loadActiveSkills();
    loadPassiveSkills();
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
