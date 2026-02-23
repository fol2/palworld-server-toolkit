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
    playerDetailCache: {},
    discoveryStatus: 'unknown',
    discoveryFound: null,
    discoveryTotal: null,
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
/* Element icons — original game PNGs from palworld.wiki.gg */
const ELEM_ICONS = {
    Fire: '<img src="icons/elem/fire.png" alt="Fire">',
    Water: '<img src="icons/elem/water.png" alt="Water">',
    Ice: '<img src="icons/elem/ice.png" alt="Ice">',
    Electricity: '<img src="icons/elem/electric.png" alt="Electricity">',
    Earth: '<img src="icons/elem/ground.png" alt="Earth">',
    Dark: '<img src="icons/elem/dark.png" alt="Dark">',
    Dragon: '<img src="icons/elem/dragon.png" alt="Dragon">',
    Leaf: '<img src="icons/elem/grass.png" alt="Leaf">',
    Normal: '<img src="icons/elem/neutral.png" alt="Normal">',
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

/* Work suitability icons — original game PNGs from palworld.wiki.gg (Oil Extraction: custom SVG) */
const WORK_ICONS = {
    'Kindling': '<img src="icons/work/kindling.png" alt="Kindling">',
    'Watering': '<img src="icons/work/watering.png" alt="Watering">',
    'Planting': '<img src="icons/work/planting.png" alt="Planting">',
    'Generating Electricity': '<img src="icons/work/generating_electricity.png" alt="Generating Electricity">',
    'Handiwork': '<img src="icons/work/handiwork.png" alt="Handiwork">',
    'Gathering': '<img src="icons/work/gathering.png" alt="Gathering">',
    'Lumbering': '<img src="icons/work/lumbering.png" alt="Lumbering">',
    'Mining': '<img src="icons/work/mining.png" alt="Mining">',
    'Medicine Production': '<img src="icons/work/medicine_production.png" alt="Medicine Production">',
    'Cooling': '<img src="icons/work/cooling.png" alt="Cooling">',
    'Transporting': '<img src="icons/work/transporting.png" alt="Transporting">',
    'Farming': '<img src="icons/work/farming.png" alt="Farming">',
    'Crude Oil Extraction': '<svg viewBox="0 0 16 16"><path fill="currentColor" d="M8 1L5 7.5a3 3 0 006 0L8 1zM4 12h8a1 1 0 011 1v1a1 1 0 01-1 1H4a1 1 0 01-1-1v-1a1 1 0 011-1z"/></svg>',
};

/* Partner skill type icons — original game assets from Palworld Fandom wiki */
const PS_ICONS = {
    fly:    '<img src="icons/ps/fly.webp" alt="Flying">',
    ride:   '<img src="icons/ps/ride.webp" alt="Riding">',
    swim:   '<img src="icons/ps/swim.webp" alt="Swimming">',
    combat: '<img src="icons/ps/combat.webp" alt="Combat">',
    shield: '<img src="icons/ps/shield.webp" alt="Shield">',
    heal:   '<img src="icons/ps/heal.webp" alt="Heal">',
    ranch:  '<img src="icons/ps/ranch.webp" alt="Ranch">',
    carry:  '<img src="icons/ps/carry.webp" alt="Carry">',
    speed:  '<img src="icons/ps/speed.webp" alt="Speed">',
    sanity: '<img src="icons/ps/sanity.webp" alt="Sanity">',
    buff:   '<img src="icons/ps/buff.webp" alt="Buff">',
    gun:    '<img src="icons/ps/gun.webp" alt="Ranged">',
    thief:  '<img src="icons/ps/thief.webp" alt="Thief">',
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

/* Track which party pal editor is expanded (-1 = none) */
let expandedPalIdx = -1;

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
    // Try /api/players/live first (merged Lua+REST), fallback to /api/players
    let data = await apiGet('/api/players/live');
    if (!data || !data.players) {
        data = await apiGet('/api/players');
    }
    if (!data) return;

    state.players = data.players || [];
    state.playerSource = data.source || 'rcon';

    // Capture discovery status from response
    if (data.discovery !== undefined) state.discoveryStatus = data.discovery;
    if (data.discovery_found !== undefined) state.discoveryFound = data.discovery_found;
    if (data.discovery_total !== undefined) state.discoveryTotal = data.discovery_total;

    if (!state.selectedPlayer && state.players.length > 0) {
        state.selectedPlayer = state.players[0].name;
    }

    renderPlayers();
    renderPlayerActions();
    updateAllTargetDropdowns();
    updateSourceBadge();
    updateDiscoveryIndicator();

    document.getElementById('online-count').textContent = state.players.length;
}

function renderPlayers() {
    const el = document.getElementById('player-list');
    if (state.players.length === 0) {
        el.innerHTML = '<div class="empty-state">No players online</div>';
        return;
    }

    const hasRichData = state.playerSource === 'rest_api' || state.playerSource === 'lua_mod';
    const isLua = state.playerSource === 'lua_mod';

    el.innerHTML = state.players.map(p => {
        const sel = p.name === state.selectedPlayer ? ' selected' : '';
        let metaHtml = '';
        if (hasRichData) {
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
            if (isLua && p.party_count != null) {
                parts.push('<span class="player-party-count">Party: ' + p.party_count + '</span>');
            }
            if (parts.length > 0) {
                metaHtml = '<div class="player-meta">' + parts.join('<span class="sep"> | </span>') + '</div>';
            }
        }

        const levelHtml = (hasRichData && p.level) ? '<span class="player-level">Lv' + p.level + '</span>' : '';

        // HP bar (when Lua data available)
        let hpHtml = '';
        if (isLua && p.hp_rate != null) {
            const pct = Math.min(p.hp_rate * 100, 100).toFixed(0);
            hpHtml = '<div class="player-hp-bar">' +
                '<div class="player-hp-bg"><div class="player-hp-fill" style="width:' + pct + '%"></div></div>' +
                '<span class="player-hp-text">' + pct + '%</span>' +
            '</div>';
        }

        return '<div class="player-item' + sel + '" onclick="selectPlayer(\'' + esc(p.name) + '\')">' +
            '<span class="player-dot"></span>' +
            '<div class="player-info">' +
                '<div class="player-main">' +
                    '<span class="player-name">' + esc(p.name) + '</span>' +
                    levelHtml +
                '</div>' +
                hpHtml +
                metaHtml +
            '</div>' +
        '</div>';
    }).join('');
}

function renderPlayerActions() {
    const el = document.getElementById('player-actions-content');
    const p = state.players.find(pl => pl.name === state.selectedPlayer);

    // Skip full rebuild when pal manager is open — prevents destroying the panel
    if (palManagerOpen && p && document.getElementById('pm-overlay')) {
        return;
    }

    if (!p) {
        el.innerHTML = '<div class="empty-guide">' +
            '<div class="empty-guide-title">Player Actions</div>' +
            '<div class="empty-guide-desc">Select a player from the list on the left to see their details and available admin actions.</div>' +
            '<div class="empty-guide-steps">' +
                '<div class="empty-guide-step"><span class="empty-guide-num">1</span> Click a player name in the Online list</div>' +
                '<div class="empty-guide-step"><span class="empty-guide-num">2</span> Give EXP, kick, ban, freeze, or teleport</div>' +
                '<div class="empty-guide-step"><span class="empty-guide-num">3</span> With MOD source: see HP, ATK, DEF, SHOT, Craft Speed</div>' +
            '</div></div>';
        return;
    }

    const hasRichData = state.playerSource === 'rest_api' || state.playerSource === 'lua_mod';
    const isLua = state.playerSource === 'lua_mod';
    const pingText = (p.ping != null) ? Math.round(p.ping) + 'ms' : 'N/A';
    const locText = (p.location_x != null && p.location_y != null)
        ? '(' + Math.round(p.location_x) + ', ' + Math.round(p.location_y) + ')' : 'N/A';
    const levelText = p.level != null ? 'Lv' + p.level : '';

    let statsHtml = '';
    if (hasRichData) {
        statsHtml = '<div class="pa-stats">' + levelText + '  |  Ping: ' + pingText + '  |  Pos: ' + locText + '</div>';
    }

    // Merge live list data with cached detail data for flicker-free rendering
    const cached = state.playerDetailCache[p.name] || {};
    const hpRate = p.hp_rate != null ? p.hp_rate : cached.hp_rate;
    const atk = p.attack != null ? p.attack : cached.attack;
    const def = p.defense != null ? p.defense : cached.defense;
    const shot = cached.shot_attack;
    const craft = cached.craft_speed;
    const food = p.fullstomach != null ? p.fullstomach : cached.fullstomach;
    const foodMax = p.max_fullstomach != null ? p.max_fullstomach : cached.max_fullstomach;
    const san = p.sanity != null ? p.sanity : cached.sanity;
    const sanMax = p.max_sanity != null ? p.max_sanity : cached.max_sanity;

    // HP bar (immediate from live + cache, no async gap)
    let hpBarHtml = '';
    if (isLua && hpRate != null) {
        const pct = Math.min(hpRate * 100, 100).toFixed(0);
        hpBarHtml = '<div class="pa-hp-bar">' +
            '<span class="pa-stat-label">HP</span>' +
            '<div class="pa-hp-bg"><div class="pa-hp-fill" style="width:' + pct + '%"></div></div>' +
            '<span class="pa-hp-text">' + pct + '%</span>' +
        '</div>';
    }
    // Fullness bar
    if (isLua && food != null && foodMax != null && foodMax > 0) {
        const foodPct = Math.min((food / foodMax) * 100, 100).toFixed(0);
        hpBarHtml += '<div class="pa-hp-bar pa-food-bar">' +
            '<span class="pa-stat-label">FOOD</span>' +
            '<div class="pa-hp-bg"><div class="pa-hp-fill pa-food-fill" style="width:' + foodPct + '%"></div></div>' +
            '<span class="pa-hp-text">' + Math.round(food) + ' / ' + Math.round(foodMax) + '</span>' +
        '</div>';
    }
    // Sanity bar
    if (isLua && san != null && sanMax != null && sanMax > 0) {
        const sanPct = Math.min((san / sanMax) * 100, 100).toFixed(0);
        hpBarHtml += '<div class="pa-hp-bar pa-san-bar">' +
            '<span class="pa-stat-label">SAN</span>' +
            '<div class="pa-hp-bg"><div class="pa-hp-fill pa-san-fill" style="width:' + sanPct + '%"></div></div>' +
            '<span class="pa-hp-text">' + Math.round(san) + ' / ' + Math.round(sanMax) + '</span>' +
        '</div>';
    }
    // Stats row (immediate from live + cache)
    let statsRowHtml = '';
    if (isLua && (atk != null || def != null || shot != null || craft != null)) {
        statsRowHtml = '<div id="pa-stats-anchor"><div class="pa-stats-row">';
        if (atk != null) statsRowHtml += '<div class="pa-stat"><span class="pa-stat-label">ATK</span> <span class="pa-stat-value">' + atk + '</span></div>';
        if (shot != null) statsRowHtml += '<div class="pa-stat"><span class="pa-stat-label">SHOT</span> <span class="pa-stat-value">' + shot + '</span></div>';
        if (def != null) statsRowHtml += '<div class="pa-stat"><span class="pa-stat-label">DEF</span> <span class="pa-stat-value">' + def + '</span></div>';
        if (craft != null) statsRowHtml += '<div class="pa-stat"><span class="pa-stat-label">CRAFT</span> <span class="pa-stat-value">' + craft + '</span></div>';
        statsRowHtml += '</div></div>';
    } else {
        statsRowHtml = isLua ? '<div id="pa-stats-anchor"></div>' : '';
    }

    // Inventory + party pals + pal manager containers
    let detailSectionsHtml =
        '<div id="pa-detail-sections">' +
            '<div id="pa-inventory-section"></div>' +
            '<div id="pa-party-section"></div>' +
            '<div class="action-group">' +
                '<button class="btn btn-accent btn-sm" onclick="togglePalManager()" style="width:100%">Manage All Pals (Party + Box)</button>' +
            '</div>' +
        '</div>';

    el.innerHTML =
        '<div class="pa-header">' +
            '<div class="pa-name">' + esc(p.name) + '</div>' +
            statsHtml +
            hpBarHtml +
            statsRowHtml +
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
        '</div>' +

        '<div class="action-group">' +
            '<div class="action-group-label">Admin Stats <span class="badge">Experimental</span></div>' +
            '<div class="action-row" style="margin-bottom:6px">' +
                '<button class="btn btn-accent btn-sm" onclick="editPlayerStat(\'full_power\')">MAX ALL</button>' +
            '</div>' +
            '<div class="stat-editor-grid">' +
                '<div class="stat-editor-row"><span>HP</span><input type="number" id="stat-hp" class="input mono" value="10000" min="1" style="width:80px"><button class="btn btn-xs" onclick="editPlayerStat(\'set_hp\',\'stat-hp\')">Set</button></div>' +
                '<div class="stat-editor-row"><span>SP</span><input type="number" id="stat-sp" class="input mono" value="10000" min="1" style="width:80px"><button class="btn btn-xs" onclick="editPlayerStat(\'set_sp\',\'stat-sp\')">Set</button></div>' +
                '<div class="stat-editor-row"><span>Money</span><input type="number" id="stat-money" class="input mono" value="1000000" min="1" style="width:80px"><button class="btn btn-xs" onclick="editPlayerStat(\'add_money\',\'stat-money\')">Add</button></div>' +
                '<div class="stat-editor-row"><span>Tech Pts</span><input type="number" id="stat-tech" class="input mono" value="100" min="1" style="width:80px"><button class="btn btn-xs" onclick="editPlayerStat(\'add_tech_points\',\'stat-tech\')">Add</button></div>' +
                '<div class="stat-editor-row"><span>Boss Tech</span><input type="number" id="stat-btech" class="input mono" value="100" min="1" style="width:80px"><button class="btn btn-xs" onclick="editPlayerStat(\'add_boss_tech\',\'stat-btech\')">Add</button></div>' +
                '<div class="stat-editor-row"><span>Inv Size</span><input type="number" id="stat-inv" class="input mono" value="100" min="1" style="width:80px"><button class="btn btn-xs" onclick="editPlayerStat(\'set_inventory_size\',\'stat-inv\')">Set</button></div>' +
            '</div>' +
        '</div>' +

        detailSectionsHtml;

    // Async: fetch player detail for inventory + party pals (try regardless of source)
    if (p.name) {
        fetchPlayerDetail(p.name);
    }
}

/* Fetch detailed player data (inventory, party pals) from Lua mod */
async function fetchPlayerDetail(playerName) {
    const enc = encodeURIComponent(playerName);
    const [detailResp, palsResp, invResp] = await Promise.all([
        apiGet('/api/player/' + enc),
        apiGet('/api/player/' + enc + '/pals'),
        apiGet('/api/player/' + enc + '/inventory'),
    ]);
    // Guard: player may have changed during the await
    if (state.selectedPlayer !== playerName) return;

    // data may be empty if detail endpoint fails; null-checks handle it downstream
    const data = (detailResp && detailResp.success !== false) ? detailResp : {};

    // Cache detail data for flicker-free re-renders
    state.playerDetailCache[playerName] = data;

    // Update bars in-place (detail may have fresher data than live list)
    if (data.hp_rate != null) {
        const pct = Math.min(data.hp_rate * 100, 100).toFixed(0);
        const hpEl = document.querySelector('.pa-hp-bar:not(.pa-food-bar):not(.pa-san-bar)');
        if (hpEl) {
            hpEl.querySelector('.pa-hp-fill').style.width = pct + '%';
            hpEl.querySelector('.pa-hp-text').textContent = pct + '%';
        }
    }
    if (data.fullstomach != null && data.max_fullstomach != null && data.max_fullstomach > 0) {
        const foodPct = Math.min((data.fullstomach / data.max_fullstomach) * 100, 100).toFixed(0);
        const foodEl = document.querySelector('.pa-food-bar');
        if (foodEl) {
            foodEl.querySelector('.pa-hp-fill').style.width = foodPct + '%';
            foodEl.querySelector('.pa-hp-text').textContent = Math.round(data.fullstomach) + ' / ' + Math.round(data.max_fullstomach);
        }
    }
    if (data.sanity != null && data.max_sanity != null && data.max_sanity > 0) {
        const sanPct = Math.min((data.sanity / data.max_sanity) * 100, 100).toFixed(0);
        const sanEl = document.querySelector('.pa-san-bar');
        if (sanEl) {
            sanEl.querySelector('.pa-hp-fill').style.width = sanPct + '%';
            sanEl.querySelector('.pa-hp-text').textContent = Math.round(data.sanity) + ' / ' + Math.round(data.max_sanity);
        }
    }

    // Update stats row in-place
    const anchor = document.getElementById('pa-stats-anchor');
    if (anchor) {
        const hasStats = data.attack != null || data.defense != null || data.shot_attack != null || data.craft_speed != null;
        if (hasStats) {
            let statsRow = '<div class="pa-stats-row">';
            if (data.attack != null) statsRow += '<div class="pa-stat"><span class="pa-stat-label">ATK</span> <span class="pa-stat-value">' + data.attack + '</span></div>';
            if (data.shot_attack != null) statsRow += '<div class="pa-stat"><span class="pa-stat-label">SHOT</span> <span class="pa-stat-value">' + data.shot_attack + '</span></div>';
            if (data.defense != null) statsRow += '<div class="pa-stat"><span class="pa-stat-label">DEF</span> <span class="pa-stat-value">' + data.defense + '</span></div>';
            if (data.craft_speed != null) statsRow += '<div class="pa-stat"><span class="pa-stat-label">CRAFT</span> <span class="pa-stat-value">' + data.craft_speed + '</span></div>';
            statsRow += '</div>';
            anchor.innerHTML = statsRow;
        }

        // Discovery note
        if (!anchor.querySelector('.pa-discovery-note')) {
            const hasAnyData = data.hp_rate != null || data.attack != null || data.defense != null;
            if (state.discoveryStatus === 'pending') {
                anchor.insertAdjacentHTML('beforeend',
                    '<div class="pa-discovery-note">Auto-discovery in progress — more data will appear once property scanning completes.</div>');
            } else if (state.discoveryStatus === 'ok' && !hasAnyData) {
                anchor.insertAdjacentHTML('beforeend',
                    '<div class="pa-discovery-note">Discovery complete but no player data extracted. Check discovery-log.json for raw property names.</div>');
            }
        }
    }

    // Inventory section (from dedicated endpoint, fallback to detail data)
    const invItems = (invResp && invResp.success !== false && invResp.items) ? invResp.items : (data.inventory || []);
    const invNote = (invResp && invResp.success === false) ? invResp.message :
                    (invResp && invResp.debug) ? invResp.debug : null;
    console.log('[PalEditor] inventory resp:', JSON.stringify(invResp), '→ items:', invItems.length);
    renderPlayerInventory(invItems, invNote);

    // Party pals section (from dedicated endpoint with full stats, fallback to detail)
    const palsNote = (palsResp && palsResp.note) ? palsResp.note :
                     (palsResp && palsResp.debug) ? palsResp.debug :
                     (palsResp && palsResp.success === false) ? palsResp.message : null;
    const palsList = (palsResp && palsResp.success !== false && palsResp.pals) ? palsResp.pals : (data.party_pals || []);
    console.log('[PalEditor] pals resp:', JSON.stringify(palsResp), '→ pals:', palsList.length);
    state.currentPalData = palsList;
    renderPlayerPartyPals(palsList, palsNote);
}

function renderPlayerInventory(items, note) {
    var el = document.getElementById('pa-inventory-section');
    if (!el) return;
    if (!items || items.length === 0) {
        el.innerHTML = '<div class="action-group"><div class="action-group-label">Inventory</div>' +
            '<div class="empty-state" style="padding:8px;font-size:12px;opacity:.6">' +
            (note ? esc(note) : 'No inventory data available') + '</div></div>';
        return;
    }
    var html = '<div class="pa-inventory">' +
        '<div class="action-group-label">Inventory (' + items.length + ')</div>' +
        '<div class="pa-inv-list">';
    for (var ii = 0; ii < items.length; ii++) {
        var item = items[ii];
        var itemData = state.items.find(function(i) { return i.id === item.id; });
        var itemName = itemData ? itemData.name : item.id;
        var itemIcon = itemData ? itemData.icon : null;
        html += '<div class="pa-inv-item">' +
            iconImg(itemIcon, 20) +
            '<span class="pa-inv-name">' + esc(itemName) + '</span>' +
            '<span class="pa-inv-qty">x' + (item.qty || item.count || 1) + '</span>' +
        '</div>';
    }
    html += '</div></div>';
    el.innerHTML = html;
}

function renderPlayerPartyPals(pals, note) {
    var partyEl = document.getElementById('pa-party-section');
    if (!partyEl) return;
    if (!pals || pals.length === 0) {
        partyEl.innerHTML = '<div class="action-group"><div class="action-group-label">Party Pals</div>' +
            '<div class="empty-state" style="padding:8px;font-size:12px;opacity:.6">' +
            (note ? esc(note) : 'No party pals found — player may need to be in-game with pals in party') + '</div></div>';
        return;
    }

    var html = '<div class="pa-party">' +
        '<div class="action-group-label">Party Pals (' + pals.length + ')</div>' +
        '<div class="pa-party-grid">';

    pals.forEach(function(pal, idx) {
        var palData = state.palDb[pal.character_id];
        var displayName = pal.nickname || (palData ? palData.name : null) || pal.character_id || '???';
        var palIcon = palData ? palData.icon : null;
        var levelStr = pal.level != null ? 'Lv' + pal.level : '';
        var isExpanded = expandedPalIdx === idx;

        // Rank stars (condense rank 0-4)
        var rankHtml = '';
        if (pal.rank != null && pal.rank > 0) {
            rankHtml = '<span class="pal-rank-stars">';
            for (var ri = 0; ri < pal.rank; ri++) rankHtml += '<span class="pal-rank-star">\u2605</span>';
            rankHtml += '</span>';
        }
        // Dead / gender indicators
        var deadBadge = pal.is_dead ? '<span class="pal-dead-badge">DEAD</span>' : '';
        var genderIcon = pal.gender === 'Male' ? '<span class="pal-gender male">\u2642</span>' :
                         pal.gender === 'Female' ? '<span class="pal-gender female">\u2640</span>' : '';

        // Compact stats
        var statsHtml = '';
        if (pal.melee_attack != null || pal.defense != null) {
            statsHtml = '<div class="pal-card-stats">';
            if (pal.max_hp != null) statsHtml += '<span>HP:' + Math.floor(pal.max_hp / 1000) + '</span>';
            if (pal.melee_attack != null) statsHtml += '<span>ATK:' + pal.melee_attack + '</span>';
            if (pal.defense != null) statsHtml += '<span>DEF:' + pal.defense + '</span>';
            if (pal.craft_speed != null) statsHtml += '<span>SPD:' + pal.craft_speed + '</span>';
            statsHtml += '</div>';
        }

        // Passive badges
        var passivesHtml = '';
        if (pal.passives && pal.passives.length > 0) {
            passivesHtml = '<div class="pal-card-passives">';
            for (var pi = 0; pi < pal.passives.length; pi++) {
                var ps = state.passiveSkills[pal.passives[pi]];
                passivesHtml += '<span class="pal-passive-badge" title="' + esc(pal.passives[pi]) + '">' + esc(ps ? ps.name : pal.passives[pi]) + '</span>';
            }
            passivesHtml += '</div>';
        }

        html += '<div class="pa-pal-card-v2' + (isExpanded ? ' expanded' : '') + (pal.is_dead ? ' dead' : '') + '">' +
            '<div class="pal-card-header" onclick="togglePalEditor(' + idx + ')">' +
                iconImg(palIcon, 32) +
                '<div class="pal-card-info">' +
                    '<div class="pal-card-top">' +
                        '<span class="pal-card-name">' + esc(displayName) + '</span>' +
                        genderIcon + rankHtml + deadBadge +
                    '</div>' +
                    statsHtml +
                    passivesHtml +
                '</div>' +
                '<span class="pal-card-level">' + levelStr + '</span>' +
                '<span class="pal-card-expand">' + (isExpanded ? '\u25BE' : '\u25B8') + '</span>' +
            '</div>';

        if (isExpanded) {
            html += renderPalEditorPanel(pal, idx);
        }
        html += '</div>';
    });

    html += '</div></div>';
    partyEl.innerHTML = html;
}

function renderPalEditorPanel(pal, palIdx) {
    var html = '<div class="pal-editor-panel">';

    // ── Heal ──
    html += '<div class="pal-editor-section">' +
        '<div class="pal-editor-label">Health</div>' +
        '<div class="action-row">' +
            '<button class="btn btn-success btn-sm" onclick="palAction(' + palIdx + ',\'heal\')">Full Heal</button>' +
            '<select class="input" id="pal-health-' + palIdx + '" style="width:120px">' +
                '<option value="0"' + (pal.physical_health === 0 ? ' selected' : '') + '>Healthy</option>' +
                '<option value="1"' + (pal.physical_health === 1 ? ' selected' : '') + '>Injured</option>' +
                '<option value="2"' + (pal.physical_health === 2 ? ' selected' : '') + '>Depressed</option>' +
            '</select>' +
            '<button class="btn btn-sm" onclick="palAction(' + palIdx + ',\'set_physical_health\',{value:+document.getElementById(\'pal-health-' + palIdx + '\').value})">Set</button>' +
        '</div></div>';

    // ── Passives ──
    html += '<div class="pal-editor-section">' +
        '<div class="pal-editor-label">Passives</div>';
    if (pal.passives && pal.passives.length > 0) {
        html += '<div class="pal-editor-tags">';
        for (var i = 0; i < pal.passives.length; i++) {
            var ps = state.passiveSkills[pal.passives[i]];
            html += '<span class="pal-editor-tag">' + esc(ps ? ps.name : pal.passives[i]) +
                '<button class="tag-remove" onclick="palAction(' + palIdx + ',\'remove_passive\',{skill_id:\'' + esc(pal.passives[i]) + '\'})">x</button></span>';
        }
        html += '</div>';
    }
    html += '<div class="action-row">' +
        '<select class="input" id="pal-add-passive-' + palIdx + '" style="flex:1;max-width:200px">';
    var pKeys = Object.keys(state.passiveSkills).sort(function(a, b) {
        return (state.passiveSkills[a].name || a).localeCompare(state.passiveSkills[b].name || b);
    });
    for (var pk = 0; pk < pKeys.length; pk++) {
        if (pal.passives && pal.passives.indexOf(pKeys[pk]) >= 0) continue;
        html += '<option value="' + esc(pKeys[pk]) + '">' + esc(state.passiveSkills[pKeys[pk]].name || pKeys[pk]) + '</option>';
    }
    html += '</select>' +
        '<button class="btn btn-sm" onclick="palAction(' + palIdx + ',\'add_passive\',{skill_id:document.getElementById(\'pal-add-passive-' + palIdx + '\').value})">Add</button>' +
    '</div></div>';

    // ── Moves ──
    html += '<div class="pal-editor-section">' +
        '<div class="pal-editor-label">Equipped Moves</div>';
    if (pal.equip_waza && pal.equip_waza.length > 0) {
        html += '<div class="pal-editor-tags">';
        for (var mi = 0; mi < pal.equip_waza.length; mi++) {
            var sk = state.activeSkills[pal.equip_waza[mi]];
            html += '<span class="pal-editor-tag">' + esc(sk ? sk.name : pal.equip_waza[mi]) +
                '<button class="tag-remove" onclick="palAction(' + palIdx + ',\'remove_move\',{waza_id:\'' + esc(pal.equip_waza[mi]) + '\'})">x</button></span>';
        }
        html += '</div>';
    }
    var availMoves = (pal.mastered_waza && pal.mastered_waza.length > 0) ? pal.mastered_waza : Object.keys(state.activeSkills);
    html += '<div class="action-row">' +
        '<select class="input" id="pal-add-move-' + palIdx + '" style="flex:1;max-width:200px">';
    for (var mj = 0; mj < availMoves.length; mj++) {
        if (pal.equip_waza && pal.equip_waza.indexOf(availMoves[mj]) >= 0) continue;
        var msk = state.activeSkills[availMoves[mj]];
        html += '<option value="' + esc(availMoves[mj]) + '">' + esc(msk ? msk.name : availMoves[mj]) + '</option>';
    }
    html += '</select>' +
        '<button class="btn btn-sm" onclick="palAction(' + palIdx + ',\'add_move\',{waza_id:document.getElementById(\'pal-add-move-' + palIdx + '\').value})">Add</button>' +
        '<button class="btn btn-danger btn-sm" onclick="palAction(' + palIdx + ',\'clear_moves\')">Clear All</button>' +
    '</div></div>';

    // ── Stat Points ──
    html += '<div class="pal-editor-section">' +
        '<div class="pal-editor-label">Stat Points <span class="dim">(Unused: ' + (pal.unused_points || 0) + ')</span></div>' +
        '<div class="stat-editor-grid">' +
            '<div class="stat-editor-row"><span>HP</span><input type="number" id="pal-pts-hp-' + palIdx + '" class="input mono" value="' + (pal.hp_points || 0) + '" min="0" style="width:60px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_status_point\',{stat_name:\'HP\',value:+document.getElementById(\'pal-pts-hp-' + palIdx + '\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>ATK</span><input type="number" id="pal-pts-atk-' + palIdx + '" class="input mono" value="' + (pal.atk_points || 0) + '" min="0" style="width:60px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_status_point\',{stat_name:\'Attack\',value:+document.getElementById(\'pal-pts-atk-' + palIdx + '\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>DEF</span><input type="number" id="pal-pts-def-' + palIdx + '" class="input mono" value="' + (pal.def_points || 0) + '" min="0" style="width:60px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_status_point\',{stat_name:\'Defense\',value:+document.getElementById(\'pal-pts-def-' + palIdx + '\').value})">Set</button></div>' +
        '</div></div>';

    // ── Friendship ──
    html += '<div class="pal-editor-section">' +
        '<div class="pal-editor-label">Friendship <span class="dim">(Rank ' + (pal.friendship_rank || 0) + ' | ' + (pal.friendship_point || 0) + ' pts)</span></div>' +
        '<div class="action-row">' +
            '<input type="number" id="pal-friend-' + palIdx + '" class="input mono" value="100" min="1" style="width:80px">' +
            '<button class="btn btn-sm" onclick="palAction(' + palIdx + ',\'add_friendship\',{value:+document.getElementById(\'pal-friend-' + palIdx + '\').value||100})">Add Points</button>' +
        '</div></div>';

    // ── Ranks (experimental) ──
    html += '<div class="pal-editor-section">' +
        '<div class="pal-editor-label">Ranks <span class="badge">Experimental</span></div>' +
        '<div class="pal-editor-hint">Uses CheatManager — may only affect first party pal</div>' +
        '<div class="stat-editor-grid">' +
            '<div class="stat-editor-row"><span>Condense</span><input type="number" id="pal-rank-' + palIdx + '" class="input mono" value="' + (pal.rank || 0) + '" min="0" max="4" style="width:50px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_rank\',{value:+document.getElementById(\'pal-rank-' + palIdx + '\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>HP Rank</span><input type="number" id="pal-hprank-' + palIdx + '" class="input mono" value="' + (pal.hp_rank || 0) + '" min="0" style="width:50px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_hp_rank\',{value:+document.getElementById(\'pal-hprank-' + palIdx + '\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>ATK Rank</span><input type="number" id="pal-atkrank-' + palIdx + '" class="input mono" value="' + (pal.attack_rank || 0) + '" min="0" style="width:50px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_atk_rank\',{value:+document.getElementById(\'pal-atkrank-' + palIdx + '\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>DEF Rank</span><input type="number" id="pal-defrank-' + palIdx + '" class="input mono" value="' + (pal.defence_rank || 0) + '" min="0" style="width:50px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_def_rank\',{value:+document.getElementById(\'pal-defrank-' + palIdx + '\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>WS Rank</span><input type="number" id="pal-wsrank-' + palIdx + '" class="input mono" value="0" min="0" style="width:50px"><button class="btn btn-xs" onclick="palAction(' + palIdx + ',\'set_ws_rank\',{value:+document.getElementById(\'pal-wsrank-' + palIdx + '\').value})">Set</button></div>' +
        '</div></div>';

    html += '</div>';
    return html;
}

function togglePalEditor(idx) {
    expandedPalIdx = expandedPalIdx === idx ? -1 : idx;
    if (state.currentPalData) {
        renderPlayerPartyPals(state.currentPalData);
    }
}

async function palAction(palIdx, action, extraParams) {
    var playerName = state.selectedPlayer;
    if (!playerName) { addLog('No player selected', 'err'); return; }

    var body = { action: action, pal_index: palIdx };
    if (extraParams) {
        for (var k in extraParams) { body[k] = extraParams[k]; }
    }

    addLog('Pal: ' + action + ' on pal #' + palIdx, 'info');
    var result = await apiPost('/api/player/' + encodeURIComponent(playerName) + '/pal/edit', body);
    if (result && result.success) {
        addLog(result.message || 'OK', 'ok');
    } else {
        addLog('Failed: ' + (result ? result.message : 'No response'), 'err');
    }
    refreshPalData(playerName);
}

async function refreshPalData(playerName) {
    var palsResp = await apiGet('/api/player/' + encodeURIComponent(playerName) + '/pals');
    if (state.selectedPlayer !== playerName) return;
    var pals = (palsResp && palsResp.success !== false && palsResp.pals) ? palsResp.pals : [];
    state.currentPalData = pals;
    renderPlayerPartyPals(pals);
}

/* ── Pal Manager (fullscreen modal) ────────────────────────────────────────── */

let palManagerOpen = false;
let palManagerData = { party: [], box: [], box_pages: 0, box_page: 0 };
let palManagerBoxPage = 0;
let palManagerSelectedPal = null;

function togglePalManager() {
    palManagerOpen = !palManagerOpen;
    var overlay = document.getElementById('pm-overlay');
    if (!overlay) {
        // Create overlay once, append to body
        overlay = document.createElement('div');
        overlay.id = 'pm-overlay';
        overlay.className = 'pm-overlay';
        overlay.innerHTML =
            '<div class="pm-modal">' +
                '<div class="pm-modal-header">' +
                    '<h3>PAL MANAGER</h3>' +
                    '<span class="pm-player-name" id="pm-player-label"></span>' +
                    '<span class="spacer"></span>' +
                    '<button class="btn btn-sm" onclick="togglePalManager()">Close</button>' +
                '</div>' +
                '<div class="pm-modal-body">' +
                    '<div class="pm-list-pane" id="pm-list-pane">' +
                        '<div class="empty-state">Loading...</div>' +
                    '</div>' +
                    '<div class="pm-detail-pane" id="pm-detail-pane">' +
                        '<div class="empty-state">Select a pal</div>' +
                    '</div>' +
                '</div>' +
            '</div>';
        document.body.appendChild(overlay);
    }
    if (palManagerOpen) {
        overlay.classList.add('open');
        document.body.classList.add('pm-no-scroll');
        document.getElementById('pm-player-label').textContent = state.selectedPlayer || '';
        if (state.selectedPlayer) loadPalManager(state.selectedPlayer);
    } else {
        overlay.classList.remove('open');
        document.body.classList.remove('pm-no-scroll');
    }
}

async function loadPalManager(playerName, page) {
    if (page == null) page = palManagerBoxPage;
    var enc = encodeURIComponent(playerName);
    var resp = await apiGet('/api/player/' + enc + '/all-pals?page=' + page + '&page_size=30');
    if (!resp || state.selectedPlayer !== playerName) return;

    palManagerData = {
        party: resp.party || [],
        box: resp.box || [],
        box_pages: resp.box_pages || 0,
        box_page: resp.box_page || 0,
        box_count: resp.box_count || 0,
        party_debug: resp.party_debug || '',
    };
    palManagerBoxPage = palManagerData.box_page;
    renderPalManagerList();
    renderPalManagerDetailPane();
}

function renderPalManagerList() {
    var pane = document.getElementById('pm-list-pane');
    if (!pane) return;

    // Party section
    var html = '<div class="pm-section">' +
        '<div class="pm-section-label">Party (' + palManagerData.party.length + ')</div>' +
        '<div class="pm-pal-grid">';
    palManagerData.party.forEach(function(pal) { html += renderPalManagerCard(pal); });
    if (palManagerData.party.length === 0) {
        var dbg = palManagerData.party_debug || '';
        html += '<div class="empty-state" style="font-size:11px">No party pals<br><span class="mono dim" style="font-size:9px">' + esc(dbg) + '</span></div>';
    }
    html += '</div></div>';

    // Box section
    html += '<div class="pm-section">' +
        '<div class="pm-section-label">Pal Box' +
            (palManagerData.box_pages > 0 ? ' — Page ' + (palManagerData.box_page + 1) + '/' + palManagerData.box_pages : '') +
        '</div>';
    if (palManagerData.box_pages > 1) {
        html += '<div class="pm-pagination">';
        for (var p = 0; p < palManagerData.box_pages; p++) {
            html += '<button class="btn btn-xs' + (p === palManagerData.box_page ? ' btn-accent' : '') + '" ' +
                'onclick="palManagerGoPage(' + p + ')">' + (p + 1) + '</button>';
        }
        html += '</div>';
    }
    html += '<div class="pm-pal-grid">';
    palManagerData.box.forEach(function(pal) { html += renderPalManagerCard(pal); });
    if (palManagerData.box.length === 0 && palManagerData.box_pages > 0) html += '<div class="empty-state">Empty page</div>';
    else if (palManagerData.box_pages === 0) html += '<div class="empty-state">Pal box not accessible</div>';
    html += '</div></div>';

    pane.innerHTML = html;
}

function renderPalManagerCard(pal) {
    var palData = state.palDb[pal.character_id];
    var displayName = pal.nickname || (palData ? palData.name : null) || pal.character_id || '???';
    var palIcon = palData ? palData.icon : null;
    var levelStr = pal.level != null ? 'Lv' + pal.level : '';
    var isSelected = palManagerSelectedPal &&
        palManagerSelectedPal.source === pal.source &&
        ((pal.source === 'party' && palManagerSelectedPal.index === pal.index) ||
         (pal.source === 'box' && palManagerSelectedPal.box_page === pal.box_page && palManagerSelectedPal.slot_index === pal.slot_index));

    var rankHtml = '';
    if (pal.rank != null && pal.rank > 0) {
        rankHtml = '<span class="pal-rank-stars">';
        for (var ri = 0; ri < pal.rank; ri++) rankHtml += '<span class="pal-rank-star">\u2605</span>';
        rankHtml += '</span>';
    }
    var deadBadge = pal.is_dead ? '<span class="pal-dead-badge">DEAD</span>' : '';

    var elemHtml = '';
    if (palData && palData.elements) {
        palData.elements.forEach(function(e) {
            var color = ELEM_COLORS[e.id] || '#888';
            elemHtml += '<span class="pm-elem-badge" style="background:' + color + '22;color:' + color + '">' + (e.id || '') + '</span>';
        });
    }

    var clickData = pal.source === 'box'
        ? "pmSelectPal('box',-1," + pal.box_page + "," + pal.slot_index + ")"
        : "pmSelectPal('party'," + pal.index + ",0,0)";

    return '<div class="pm-card' + (isSelected ? ' selected' : '') + (pal.is_dead ? ' dead' : '') + '" onclick="' + clickData + '">' +
        iconImg(palIcon, 28) +
        '<div class="pm-card-info">' +
            '<div class="pm-card-top">' +
                '<span class="pm-card-name">' + esc(displayName) + '</span>' +
                rankHtml + deadBadge +
            '</div>' +
            '<div class="pm-card-meta">' + elemHtml + '</div>' +
        '</div>' +
        '<span class="pm-card-level">' + levelStr + '</span>' +
    '</div>';
}

function pmSelectPal(source, index, boxPage, slotIndex) {
    var pal = null;
    if (source === 'party') {
        pal = palManagerData.party.find(function(p) { return p.index === index; });
    } else {
        pal = palManagerData.box.find(function(p) { return p.box_page === boxPage && p.slot_index === slotIndex; });
    }
    if (!pal) return;
    palManagerSelectedPal = { source: source, index: index, box_page: boxPage, slot_index: slotIndex, pal: pal };
    // Update list selection highlight without full rebuild
    document.querySelectorAll('.pm-card').forEach(function(c) { c.classList.remove('selected'); });
    event.currentTarget.classList.add('selected');
    renderPalManagerDetailPane();
}

function renderPalManagerDetailPane() {
    var pane = document.getElementById('pm-detail-pane');
    if (!pane) return;
    if (!palManagerSelectedPal || !palManagerSelectedPal.pal) {
        pane.innerHTML = '<div class="empty-state">Select a pal to view and edit</div>';
        return;
    }
    pane.innerHTML = renderPalManagerDetail();
    pane.scrollTop = 0;
}

function renderPalManagerDetail() {
    var sel = palManagerSelectedPal;
    var pal = sel.pal;
    var palData = state.palDb[pal.character_id];
    var displayName = pal.nickname || (palData ? palData.name : null) || pal.character_id || '???';
    var speciesName = palData ? palData.name : pal.character_id || '???';
    var palIcon = palData ? palData.icon : null;
    var srcLabel = sel.source === 'box' ? 'Box p' + (sel.box_page + 1) + ' #' + sel.slot_index : 'Party #' + (sel.index + 1);

    var editPrefix = sel.source === 'box'
        ? "pmEditPal('box'," + sel.box_page + "," + sel.slot_index
        : "pmEditPal('party',0,0";

    var html = '<div class="pm-detail-header">' +
        iconImg(palIcon, 48) +
        '<div class="pm-detail-info">' +
            '<div class="pm-detail-name">' + esc(displayName) + '</div>' +
            '<div class="pm-detail-species">' + esc(speciesName) + ' | ' + srcLabel + '</div>' +
        '</div>' +
        '<button class="btn btn-success btn-sm" onclick="' + editPrefix + ',\'heal\')" style="margin-left:auto">Heal</button>' +
    '</div>';

    // Rename
    html += '<div class="pm-edit-section">' +
        '<div class="pm-edit-label">Nickname</div>' +
        '<div class="action-row">' +
            '<input type="text" id="pm-rename" class="input" value="' + esc(pal.nickname || '') + '" placeholder="' + esc(speciesName) + '" style="flex:1">' +
            '<button class="btn btn-sm" onclick="' + editPrefix + ',\'rename\',{nickname:document.getElementById(\'pm-rename\').value})">Set</button>' +
        '</div></div>';

    // Core stats
    html += '<div class="pm-edit-section"><div class="pm-edit-label">Stats</div><div class="pm-stats-grid">';
    if (pal.level != null) html += '<div class="pm-stat"><span>Level</span><span class="mono">' + pal.level + '</span></div>';
    if (pal.max_hp != null) html += '<div class="pm-stat"><span>HP</span><span class="mono">' + Math.floor(pal.max_hp / 1000) + '</span></div>';
    if (pal.melee_attack != null) html += '<div class="pm-stat"><span>ATK</span><span class="mono">' + pal.melee_attack + '</span></div>';
    if (pal.defense != null) html += '<div class="pm-stat"><span>DEF</span><span class="mono">' + pal.defense + '</span></div>';
    if (pal.craft_speed != null) html += '<div class="pm-stat"><span>SPD</span><span class="mono">' + pal.craft_speed + '</span></div>';
    html += '</div></div>';

    // Stat Points
    html += '<div class="pm-edit-section">' +
        '<div class="pm-edit-label">Stat Points <span class="dim">(Unused: ' + (pal.unused_points || 0) + ')</span></div>' +
        '<div class="stat-editor-grid">' +
            '<div class="stat-editor-row"><span>HP</span><input type="number" id="pm-pts-hp" class="input mono" value="' + (pal.hp_points || 0) + '" min="0" style="width:60px"><button class="btn btn-xs" onclick="' + editPrefix + ',\'set_status_point\',{stat_name:\'HP\',value:+document.getElementById(\'pm-pts-hp\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>ATK</span><input type="number" id="pm-pts-atk" class="input mono" value="' + (pal.atk_points || 0) + '" min="0" style="width:60px"><button class="btn btn-xs" onclick="' + editPrefix + ',\'set_status_point\',{stat_name:\'Attack\',value:+document.getElementById(\'pm-pts-atk\').value})">Set</button></div>' +
            '<div class="stat-editor-row"><span>DEF</span><input type="number" id="pm-pts-def" class="input mono" value="' + (pal.def_points || 0) + '" min="0" style="width:60px"><button class="btn btn-xs" onclick="' + editPrefix + ',\'set_status_point\',{stat_name:\'Defense\',value:+document.getElementById(\'pm-pts-def\').value})">Set</button></div>' +
        '</div></div>';

    // Passives
    html += '<div class="pm-edit-section"><div class="pm-edit-label">Passives</div>';
    if (pal.passives && pal.passives.length > 0) {
        html += '<div class="pal-editor-tags">';
        for (var i = 0; i < pal.passives.length; i++) {
            var ps = state.passiveSkills[pal.passives[i]];
            html += '<span class="pal-editor-tag">' + esc(ps ? ps.name : pal.passives[i]) +
                '<button class="tag-remove" onclick="' + editPrefix + ',\'remove_passive\',{skill_id:\'' + esc(pal.passives[i]) + '\'})">x</button></span>';
        }
        html += '</div>';
    }
    html += '<div class="action-row"><select class="input" id="pm-add-passive" style="flex:1">';
    var pKeys = Object.keys(state.passiveSkills).sort(function(a, b) {
        return (state.passiveSkills[a].name || a).localeCompare(state.passiveSkills[b].name || b);
    });
    for (var pk = 0; pk < pKeys.length; pk++) {
        if (pal.passives && pal.passives.indexOf(pKeys[pk]) >= 0) continue;
        html += '<option value="' + esc(pKeys[pk]) + '">' + esc(state.passiveSkills[pKeys[pk]].name || pKeys[pk]) + '</option>';
    }
    html += '</select><button class="btn btn-sm" onclick="' + editPrefix + ',\'add_passive\',{skill_id:document.getElementById(\'pm-add-passive\').value})">Add</button></div></div>';

    // Moves
    html += '<div class="pm-edit-section"><div class="pm-edit-label">Equipped Moves</div>';
    if (pal.equip_waza && pal.equip_waza.length > 0) {
        html += '<div class="pal-editor-tags">';
        for (var mi = 0; mi < pal.equip_waza.length; mi++) {
            var sk = state.activeSkills[pal.equip_waza[mi]];
            html += '<span class="pal-editor-tag">' + esc(sk ? sk.name : pal.equip_waza[mi]) +
                '<button class="tag-remove" onclick="' + editPrefix + ',\'remove_move\',{waza_id:\'' + esc(pal.equip_waza[mi]) + '\'})">x</button></span>';
        }
        html += '</div>';
    }
    var availMoves = (pal.mastered_waza && pal.mastered_waza.length > 0) ? pal.mastered_waza : Object.keys(state.activeSkills);
    html += '<div class="action-row"><select class="input" id="pm-add-move" style="flex:1">';
    for (var mj = 0; mj < availMoves.length; mj++) {
        if (pal.equip_waza && pal.equip_waza.indexOf(availMoves[mj]) >= 0) continue;
        var msk = state.activeSkills[availMoves[mj]];
        html += '<option value="' + esc(availMoves[mj]) + '">' + esc(msk ? msk.name : availMoves[mj]) + '</option>';
    }
    html += '</select><button class="btn btn-sm" onclick="' + editPrefix + ',\'add_move\',{waza_id:document.getElementById(\'pm-add-move\').value})">Add</button>' +
        '<button class="btn btn-danger btn-sm" onclick="' + editPrefix + ',\'clear_moves\')">Clear</button></div></div>';

    // Friendship
    html += '<div class="pm-edit-section">' +
        '<div class="pm-edit-label">Friendship <span class="dim">(Rank ' + (pal.friendship_rank || 0) + ' | ' + (pal.friendship_point || 0) + ' pts)</span></div>' +
        '<div class="action-row">' +
            '<input type="number" id="pm-friend" class="input mono" value="100" min="1" style="width:80px">' +
            '<button class="btn btn-sm" onclick="' + editPrefix + ',\'add_friendship\',{value:+document.getElementById(\'pm-friend\').value||100})">Add</button>' +
        '</div></div>';

    // Status
    html += '<div class="pm-edit-section"><div class="pm-edit-label">Status</div><div class="pm-stats-grid">';
    if (pal.physical_health != null) {
        var hl = ['Healthy', 'Injured', 'Depressed'];
        html += '<div class="pm-stat"><span>Health</span><span>' + (hl[pal.physical_health] || pal.physical_health) + '</span></div>';
    }
    if (pal.fullstomach_rate != null) html += '<div class="pm-stat"><span>Hunger</span><span class="mono">' + (pal.fullstomach_rate * 100).toFixed(0) + '%</span></div>';
    if (pal.sanity_rate != null) html += '<div class="pm-stat"><span>Sanity</span><span class="mono">' + (pal.sanity_rate * 100).toFixed(0) + '%</span></div>';
    html += '</div></div>';

    return html;
}

async function pmEditPal(source, boxPage, slotIndex, action, extraParams) {
    var playerName = state.selectedPlayer;
    if (!playerName) { addLog('No player selected', 'err'); return; }

    var body = { action: action, source: source };
    if (source === 'box') {
        body.box_page = boxPage;
        body.slot_index = slotIndex;
    } else {
        body.pal_index = palManagerSelectedPal ? palManagerSelectedPal.index : 0;
    }
    if (extraParams) {
        for (var k in extraParams) { body[k] = extraParams[k]; }
    }

    addLog('Pal Manager: ' + action + ' on ' + source + ' pal', 'info');
    var result = await apiPost('/api/player/' + encodeURIComponent(playerName) + '/pal/edit', body);
    if (result && result.success) {
        addLog(result.message || 'OK', 'ok');
    } else {
        addLog('Failed: ' + (result ? result.message : 'No response'), 'err');
    }
    await loadPalManager(playerName, palManagerBoxPage);
}

function palManagerGoPage(page) {
    if (!state.selectedPlayer) return;
    palManagerBoxPage = page;
    palManagerSelectedPal = null;
    loadPalManager(state.selectedPlayer, page);
}

async function editPlayerStat(action, inputId) {
    if (!state.selectedPlayer) { addLog('No player selected', 'err'); return; }
    var body = { action: action, target_player: state.selectedPlayer };
    if (inputId) {
        var el = document.getElementById(inputId);
        if (el) body.value = parseInt(el.value) || 0;
    }
    addLog('Player stat: ' + action, 'info');
    var result = await apiPost('/api/player/stats/edit', body);
    if (result && result.success) {
        addLog(result.message || 'OK', 'ok');
    } else {
        addLog('Failed: ' + (result ? result.message : 'No response'), 'err');
    }
}

function updateSourceBadge() {
    const badge = document.getElementById('chip-source');
    if (state.playerSource === 'lua_mod') {
        badge.textContent = 'MOD';
        badge.className = 'chip mod-src';
    } else if (state.playerSource === 'rest_api') {
        badge.textContent = 'REST';
        badge.className = 'chip rest';
    } else {
        badge.textContent = 'RCON';
        badge.className = 'chip rcon';
    }
}

function updateDiscoveryIndicator() {
    const chip = document.getElementById('chip-discovery');
    if (!chip) return;

    // Only show when using MOD source
    if (state.playerSource !== 'lua_mod') {
        chip.style.display = 'none';
        return;
    }

    chip.style.display = '';
    const status = state.discoveryStatus;
    const found = state.discoveryFound;
    const total = state.discoveryTotal;

    if (status === 'pending' || status === 'unknown') {
        chip.className = 'chip disc-pending';
        chip.textContent = 'DISC ...';
        chip.title = 'Auto-discovery in progress — waiting for property scan';
    } else if (status === 'ok' && total != null && total > 0) {
        if (found === total) {
            chip.className = 'chip disc-full';
            chip.textContent = 'DISC ' + found + '/' + total;
            chip.title = 'Auto-discovery complete — all ' + total + ' properties found';
        } else if (found > 0) {
            chip.className = 'chip disc-partial';
            chip.textContent = 'DISC ' + found + '/' + total;
            chip.title = 'Auto-discovery partial — ' + found + ' of ' + total + ' properties found. Check discovery-log.json for details.';
        } else {
            chip.className = 'chip disc-none';
            chip.textContent = 'DISC 0/' + total;
            chip.title = 'Auto-discovery found no matching properties. Check discovery-log.json for raw property lists.';
        }
    } else {
        chip.className = 'chip disc-pending';
        chip.textContent = 'DISC ?';
        chip.title = 'Discovery status unknown';
    }
}

function selectPlayer(name) {
    state.selectedPlayer = name;
    renderPlayers();
    renderPlayerActions();
    updateAllTargetDropdowns();
}

function updateAllTargetDropdowns() {
    const ids = ['give-target', 'spawn-target', 'tp-player', 'qt-player', 'stp-source', 'stp-dest', 'world-target'];
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
        el.innerHTML = '<div class="empty-guide">' +
            '<div class="empty-guide-title">Item Details</div>' +
            '<div class="empty-guide-desc">Select an item from the list to see its full stats, effects, and description.</div>' +
            '<div class="empty-guide-steps">' +
                '<div class="empty-guide-step"><span class="empty-guide-num">1</span> Use search or category filters to find an item</div>' +
                '<div class="empty-guide-step"><span class="empty-guide-num">2</span> Click the item to see details here</div>' +
                '<div class="empty-guide-step"><span class="empty-guide-num">3</span> Choose a target player and quantity below to give it</div>' +
            '</div></div>';
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
        el.innerHTML = '<div class="empty-guide">' +
            '<div class="empty-guide-title">Pal Details</div>' +
            '<div class="empty-guide-desc">Select a pal from the list to see stats, skills, work suitability, and partner skill info.</div>' +
            '<div class="empty-guide-steps">' +
                '<div class="empty-guide-step"><span class="empty-guide-num">1</span> Use element, work, or rarity filters to find a pal</div>' +
                '<div class="empty-guide-step"><span class="empty-guide-num">2</span> Click the pal to see full details here</div>' +
                '<div class="empty-guide-step"><span class="empty-guide-num">3</span> Choose a target player and level below to spawn it</div>' +
            '</div></div>';
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

function sendPlayerToPlayer() {
    const srcSel = document.getElementById('stp-source');
    const dstSel = document.getElementById('stp-dest');
    const source = srcSel ? srcSel.value : '';
    const dest = dstSel ? dstSel.value : '';
    if (!source) { addLog('Select a source player', 'err'); return; }
    if (!dest) { addLog('Select a destination player', 'err'); return; }
    if (source === dest) { addLog('Source and destination are the same player', 'err'); return; }
    sendCommand('send_player_to_player',
        { source_player: source, target_player: dest },
        'Sending ' + source + ' to ' + dest + '...');
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

/* ── Welcome Overlay ───────────────────────────────────────────────────────── */

function showWelcome() {
    const overlay = document.getElementById('welcome-overlay');
    if (!overlay) return;
    overlay.style.display = 'flex';
    overlay.classList.remove('hiding');
    overlay.querySelector('.welcome-card').classList.remove('hiding');
}

function dismissWelcome() {
    const overlay = document.getElementById('welcome-overlay');
    if (!overlay) return;

    const dontShow = document.getElementById('welcome-dismiss-check');
    if (dontShow && dontShow.checked) {
        localStorage.setItem('le-welcome-dismissed', '1');
    }

    overlay.classList.add('hiding');
    overlay.querySelector('.welcome-card').classList.add('hiding');
    setTimeout(() => {
        if (overlay.classList.contains('hiding')) {
            overlay.style.display = 'none';
        }
    }, 260);
}

function checkWelcome() {
    if (!localStorage.getItem('le-welcome-dismissed')) {
        showWelcome();
    }
}

/* ── Help Panel ────────────────────────────────────────────────────────────── */

let helpOpen = false;

function toggleHelp() {
    helpOpen = !helpOpen;
    const backdrop = document.getElementById('help-backdrop');
    const panel = document.getElementById('help-panel');

    if (helpOpen) {
        backdrop.style.display = 'block';
        panel.style.display = 'flex';
        void backdrop.offsetHeight;
        backdrop.classList.remove('hiding');
        panel.classList.remove('hiding');
    } else {
        backdrop.classList.add('hiding');
        panel.classList.add('hiding');
        setTimeout(() => {
            if (!helpOpen) {
                backdrop.style.display = 'none';
                panel.style.display = 'none';
            }
        }, 220);
    }
}

/* ── Hint Banners ──────────────────────────────────────────────────────────── */

function dismissHint(id) {
    const el = document.getElementById('hint-' + id);
    if (el) {
        el.style.display = 'none';
        localStorage.setItem('le-hint-' + id, '1');
    }
}

function initHints() {
    // Hide previously dismissed hints
    document.querySelectorAll('.hint-banner').forEach(el => {
        const id = el.id.startsWith('hint-') ? el.id.slice(5) : el.id;
        if (localStorage.getItem('le-hint-' + id)) {
            el.style.display = 'none';
        }
    });
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
    const targetIds = ['give-target', 'spawn-target', 'tp-player', 'qt-player', 'stp-source', 'stp-dest', 'world-target'];
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

    // Welcome overlay + hints
    checkWelcome();
    initHints();

    // Global keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        // Don't trigger shortcuts when typing in inputs
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;

        if (e.key === '?') {
            e.preventDefault();
            toggleHelp();
        }
        if (e.key === 'Escape') {
            if (helpOpen) toggleHelp();
            const welcome = document.getElementById('welcome-overlay');
            if (welcome && welcome.style.display !== 'none') dismissWelcome();
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
