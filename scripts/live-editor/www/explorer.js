/* ── UObject Explorer — LiveEditor Dev Tool ──────────────────────────────── */

const explorerState = {
    mode: 'properties', // 'properties' or 'functions'
    className: 'PalPlayerState',
    instanceIndex: 0,
    propertyPath: '',
    maxItems: 50,
    lastResult: null,
    history: [],     // breadcrumb trail: [{ className, instanceIndex, propertyPath }]
    loading: false,
    hintShown: false, // whether the post-dump drill hint has been shown
    probeResult: null, // cached probe discovery result
    probeDetailsOpen: false,
    fnFilter: '',     // function name filter (case-insensitive)
};

/* ── API ──────────────────────────────────────────────────────────────────── */

async function apiDump(params) {
    try {
        const res = await fetch('/api/dump', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(params),
        });
        return await res.json();
    } catch (e) {
        return { success: false, message: 'HTTP error: ' + e.message };
    }
}

async function apiDumpFunctions(params) {
    try {
        const res = await fetch('/api/dump-functions', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(params),
        });
        return await res.json();
    } catch (e) {
        return { success: false, message: 'HTTP error: ' + e.message };
    }
}

async function apiGenerateSDK() {
    try {
        const res = await fetch('/api/generate-sdk', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: '{}',
        });
        return await res.json();
    } catch (e) {
        return { success: false, message: 'HTTP error: ' + e.message };
    }
}

async function apiProbe(force) {
    try {
        const res = await fetch('/api/probe', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ force: !!force }),
        });
        return await res.json();
    } catch (e) {
        return { success: false, message: 'HTTP error: ' + e.message };
    }
}

/* ── Mode Toggle ──────────────────────────────────────────────────────────── */

function setMode(mode) {
    explorerState.mode = mode;
    document.getElementById('mode-props').classList.toggle('active', mode === 'properties');
    document.getElementById('mode-funcs').classList.toggle('active', mode === 'functions');
    document.getElementById('filter-row').classList.toggle('visible', mode === 'functions');
    document.getElementById('btn-gensdk').style.display = mode === 'functions' ? '' : 'none';

    // Update main button text
    const btn = document.getElementById('btn-dump');
    btn.textContent = mode === 'properties' ? 'Dump Properties' : 'Dump Functions';
}

/* ── Generate SDK ─────────────────────────────────────────────────────────── */

async function doGenerateSDK() {
    const btn = document.getElementById('btn-gensdk');
    btn.disabled = true;
    btn.textContent = 'Generating...';
    setStatus('Generating CXXHeaderDump (this may take a while)...', 'loading');

    const result = await apiGenerateSDK();

    btn.disabled = false;
    btn.textContent = 'Gen SDK';

    if (result && result.success) {
        setStatus('SDK generated: ' + (result.message || 'Check ue4ss/CXXHeaderDump/'), 'ok');
    } else {
        setStatus('SDK generation failed: ' + (result ? result.message : 'No response'), 'err');
    }
}

/* ── Controls ─────────────────────────────────────────────────────────────── */

function setPreset(className) {
    document.getElementById('class-name').value = className;
    document.getElementById('inst-idx').value = '0';
    document.getElementById('prop-path').value = '';
}

function readControls() {
    explorerState.className = document.getElementById('class-name').value.trim();
    explorerState.instanceIndex = parseInt(document.getElementById('inst-idx').value) || 0;
    explorerState.propertyPath = document.getElementById('prop-path').value.trim();
    explorerState.maxItems = parseInt(document.getElementById('max-items').value) || 50;
}

function syncControls() {
    document.getElementById('class-name').value = explorerState.className;
    document.getElementById('inst-idx').value = explorerState.instanceIndex;
    document.getElementById('prop-path').value = explorerState.propertyPath;
}

/* ── Probe (Auto-Discovery) ──────────────────────────────────────────────── */

async function doProbe(force) {
    const btn = document.getElementById('btn-probe');
    btn.disabled = true;
    btn.textContent = 'Probing...';
    setStatus('Running auto-discovery probe...', 'loading');

    const result = await apiProbe(force);

    btn.disabled = false;
    btn.textContent = 'Probe';

    if (result && result.success) {
        let data;
        try {
            data = typeof result.message === 'string' ? JSON.parse(result.message) : result.message;
        } catch (e) {
            setStatus('Probe failed: invalid response', 'err');
            return;
        }

        explorerState.probeResult = data;
        renderProbePanel(data);

        const props = data.properties || {};
        const found = Object.values(props).filter(v => v !== 'NOT_FOUND').length;
        const total = Object.keys(props).length;
        setStatus('Probe complete: ' + found + '/' + total + ' properties discovered', 'ok');
    } else {
        const msg = result ? result.message : 'No response';
        setStatus('Probe failed: ' + msg, 'err');
        renderProbeBadge('fail', 'FAILED');
    }
}

function renderProbePanel(data) {
    const panel = document.getElementById('probe-panel');
    const grid = document.getElementById('probe-grid');
    panel.classList.add('visible');

    const props = data.properties || {};
    const found = Object.values(props).filter(v => v !== 'NOT_FOUND').length;
    const total = Object.keys(props).length;

    if (found > 0) {
        renderProbeBadge('ok', found + '/' + total + ' MAPPED');
    } else {
        renderProbeBadge('pending', '0 FOUND');
    }

    // Show timestamp if available (from saved log)
    const ts = data.timestamp;
    if (ts) {
        const badge = document.getElementById('probe-badge');
        badge.title = 'Last probed: ' + ts;
    }

    // Build the detail grid
    let html = '';
    const friendlyNames = {
        ps_level: 'Player Level',
        ps_pawn: 'Pawn Reference',
        pawn_hp: 'Pawn HP',
        pawn_max_hp: 'Pawn Max HP',
        pawn_params: 'Stats Component',
        pawn_inventory: 'Inventory Component',
        pawn_pal_storage: 'Pal Storage',
        param_hp: 'Param HP',
        param_max_hp: 'Param Max HP',
        param_attack: 'Attack',
        param_defense: 'Defense',
        inv_slots: 'Inventory Slots',
    };

    for (const [key, val] of Object.entries(props)) {
        const label = friendlyNames[key] || key;
        const isMissing = val === 'NOT_FOUND';
        html += '<div class="probe-item">' +
            '<span class="probe-key">' + esc(label) + '</span>' +
            '<span class="probe-val' + (isMissing ? ' missing' : '') + '">' +
            esc(isMissing ? 'not found' : val) + '</span>' +
            '</div>';
    }

    grid.innerHTML = html;

    // Auto-show details if some properties weren't found
    if (found < total && found > 0) {
        grid.style.display = 'grid';
        explorerState.probeDetailsOpen = true;
        document.getElementById('probe-toggle').textContent = 'Hide details';
    }
}

function renderProbeBadge(type, text) {
    const badge = document.getElementById('probe-badge');
    badge.className = 'probe-badge ' + type;
    badge.textContent = text;
}

function toggleProbeDetails() {
    const grid = document.getElementById('probe-grid');
    const toggle = document.getElementById('probe-toggle');
    explorerState.probeDetailsOpen = !explorerState.probeDetailsOpen;
    grid.style.display = explorerState.probeDetailsOpen ? 'grid' : 'none';
    toggle.textContent = explorerState.probeDetailsOpen ? 'Hide details' : 'Show details';
}

/* ── Main Dump ────────────────────────────────────────────────────────────── */

async function doDump() {
    if (explorerState.mode === 'functions') {
        return doDumpFunctions();
    }
    return doDumpProperties();
}

async function doDumpProperties() {
    readControls();

    if (!explorerState.className) {
        setStatus('Enter a class name', 'err');
        return;
    }

    explorerState.loading = true;
    setStatus('Dumping ' + explorerState.className + '...', 'loading');
    document.getElementById('btn-dump').disabled = true;

    const t0 = performance.now();

    const params = {
        class_name: explorerState.className,
        instance_index: explorerState.instanceIndex,
        max_items: explorerState.maxItems,
    };
    if (explorerState.propertyPath) {
        params.property_path = explorerState.propertyPath;
    }

    const result = await apiDump(params);
    const elapsed = ((performance.now() - t0) / 1000).toFixed(2);

    explorerState.loading = false;
    document.getElementById('btn-dump').disabled = false;

    if (result && result.success) {
        // Parse the inner JSON from the message field
        let data;
        try {
            data = typeof result.message === 'string' ? JSON.parse(result.message) : result.message;
        } catch (e) {
            setStatus('Failed to parse response: ' + e.message, 'err');
            renderError('Invalid JSON in response message: ' + esc(result.message));
            return;
        }

        explorerState.lastResult = data;

        // Update history for breadcrumbs
        explorerState.history = buildHistory();

        renderBreadcrumb();
        renderInfo(data);
        renderProperties(data.properties || []);
        setStatus('OK — ' + (data.property_count || 0) + ' properties in ' + elapsed + 's', 'ok');
        document.getElementById('status-time').textContent = new Date().toLocaleTimeString('en-GB');
    } else {
        const msg = result ? result.message : 'No response from server';
        setStatus('Error: ' + msg, 'err');
        renderError(msg);
    }
}

/* ── Function Dump ────────────────────────────────────────────────────────── */

async function doDumpFunctions() {
    readControls();
    explorerState.fnFilter = (document.getElementById('fn-filter').value || '').trim();

    if (!explorerState.className) {
        setStatus('Enter a class name', 'err');
        return;
    }

    explorerState.loading = true;
    setStatus('Dumping functions for ' + explorerState.className + '...', 'loading');
    document.getElementById('btn-dump').disabled = true;

    const t0 = performance.now();

    const params = {
        class_name: explorerState.className,
        instance_index: explorerState.instanceIndex,
        max_items: explorerState.maxItems,
    };
    if (explorerState.propertyPath) {
        params.property_path = explorerState.propertyPath;
    }
    if (explorerState.fnFilter) {
        params.filter = explorerState.fnFilter;
    }

    const result = await apiDumpFunctions(params);
    const elapsed = ((performance.now() - t0) / 1000).toFixed(2);

    explorerState.loading = false;
    document.getElementById('btn-dump').disabled = false;

    if (result && result.success) {
        let data;
        try {
            data = typeof result.message === 'string' ? JSON.parse(result.message) : result.message;
        } catch (e) {
            setStatus('Failed to parse response: ' + e.message, 'err');
            renderError('Invalid JSON in response message: ' + esc(result.message));
            return;
        }

        explorerState.lastResult = data;
        explorerState.history = buildHistory();

        renderBreadcrumb();
        renderFunctionInfo(data);
        renderFunctions(data.functions || []);
        setStatus('OK — ' + (data.function_count || 0) + ' functions in ' + elapsed + 's', 'ok');
        document.getElementById('status-time').textContent = new Date().toLocaleTimeString('en-GB');
    } else {
        const msg = result ? result.message : 'No response from server';
        setStatus('Error: ' + msg, 'err');
        renderError(msg);
    }
}

/* ── Drill Down ───────────────────────────────────────────────────────────── */

function drillInto(propName) {
    readControls();
    if (explorerState.propertyPath) {
        explorerState.propertyPath += '.' + propName;
    } else {
        explorerState.propertyPath = propName;
    }
    syncControls();
    doDump();
}

function navigateTo(className, instanceIndex, propertyPath) {
    explorerState.className = className;
    explorerState.instanceIndex = instanceIndex;
    explorerState.propertyPath = propertyPath;
    syncControls();
    doDump();
}

/* ── Breadcrumb ───────────────────────────────────────────────────────────── */

function buildHistory() {
    const parts = [];
    parts.push({
        label: explorerState.className + '[' + explorerState.instanceIndex + ']',
        className: explorerState.className,
        instanceIndex: explorerState.instanceIndex,
        propertyPath: '',
    });

    if (explorerState.propertyPath) {
        const segments = explorerState.propertyPath.split('.');
        for (let i = 0; i < segments.length; i++) {
            const path = segments.slice(0, i + 1).join('.');
            parts.push({
                label: segments[i],
                className: explorerState.className,
                instanceIndex: explorerState.instanceIndex,
                propertyPath: path,
            });
        }
    }

    return parts;
}

function renderBreadcrumb() {
    const el = document.getElementById('breadcrumb');
    const history = explorerState.history;

    if (history.length === 0) {
        el.innerHTML = '<span class="bc-current">Ready</span>';
        return;
    }

    el.innerHTML = history.map((h, i) => {
        const isLast = i === history.length - 1;
        const sep = i > 0 ? '<span class="bc-sep">.</span>' : '';
        if (isLast) {
            return sep + '<span class="bc-segment bc-current">' + esc(h.label) + '</span>';
        }
        return sep + '<span class="bc-segment" onclick="navigateTo(\'' +
            esc(h.className) + '\',' + h.instanceIndex + ',\'' + esc(h.propertyPath) + '\')">' +
            esc(h.label) + '</span>';
    }).join('');
}

/* ── Rendering ────────────────────────────────────────────────────────────── */

function renderInfo(data) {
    const el = document.getElementById('results-info');
    el.style.display = 'flex';
    document.getElementById('info-class').textContent = 'Path: ' + (data.class || '?');
    document.getElementById('info-instances').textContent = 'Instances: ' + (data.instance_count || '?');
    document.getElementById('info-props').textContent = 'Properties shown: ' + (data.property_count || 0);
}

function renderProperties(props) {
    const el = document.getElementById('results');

    if (props.length === 0) {
        el.innerHTML = '<div class="empty-state">No properties found at this path.</div>';
        return;
    }

    let html = '';

    // Show a one-time hint if there are drillable properties
    if (!explorerState.hintShown) {
        const hasDrillable = props.some(p => isDrillableType(p.type, p.value));
        if (hasDrillable) {
            html += '<div class="explorer-hint">Click <strong>cyan values</strong> or ' +
                '&ldquo;Drill &rarr;&rdquo; buttons to explore nested objects. ' +
                'Use the breadcrumb bar above to navigate back.</div>';
            explorerState.hintShown = true;
        }
    }

    html += '<table><thead><tr>' +
        '<th>OFFSET</th><th>TYPE</th><th>NAME</th><th>VALUE</th><th></th>' +
        '</tr></thead><tbody>';

    for (const p of props) {
        const isDrillable = isDrillableType(p.type, p.value);
        const valueClass = getValueClass(p.type, p.value);
        const drillBtn = isDrillable
            ? '<button class="btn btn-sm" onclick="drillInto(\'' + esc(p.name) + '\')" style="padding:2px 8px;font-size:10px">Drill &rarr;</button>'
            : '';

        html += '<tr>' +
            '<td class="col-offset">0x' + (p.offset != null ? p.offset.toString(16).toUpperCase().padStart(4, '0') : '????') + '</td>' +
            '<td class="col-type">' + esc(p.type) + '</td>' +
            '<td class="col-name">' + esc(p.name) + '</td>' +
            '<td class="col-value ' + valueClass + (isDrillable ? ' drillable" onclick="drillInto(\'' + esc(p.name) + '\')"' : '"') +
                ' title="' + esc(p.value) + '">' + esc(truncate(p.value, 120)) + '</td>' +
            '<td>' + drillBtn + '</td>' +
            '</tr>';
    }

    html += '</tbody></table>';
    el.innerHTML = html;
}

function renderFunctionInfo(data) {
    const el = document.getElementById('results-info');
    el.style.display = 'flex';
    document.getElementById('info-class').textContent = 'Path: ' + (data.class || '?');
    document.getElementById('info-instances').textContent = 'Instances: ' + (data.instance_count || '?');
    document.getElementById('info-props').textContent = 'Functions shown: ' + (data.function_count || 0);
}

function renderFunctions(funcs) {
    const el = document.getElementById('results');

    if (funcs.length === 0) {
        el.innerHTML = '<div class="empty-state">No functions found' +
            (explorerState.fnFilter ? ' matching "' + esc(explorerState.fnFilter) + '"' : '') +
            '.</div>';
        return;
    }

    let html = '<table><thead><tr>' +
        '<th>NAME</th><th>PARAMETERS</th><th>RETURN</th><th>FLAGS</th>' +
        '</tr></thead><tbody>';

    for (const fn of funcs) {
        // Build params display
        let paramsHtml = '';
        if (fn.params && fn.params.length > 0) {
            paramsHtml = fn.params.map(p => {
                const cls = p.direction === 'out' ? 'param-out' : 'param-name';
                const prefix = p.direction === 'out' ? 'out ' : '';
                return '<span class="' + cls + '">' + prefix + esc(p.name) + '</span>' +
                    '<span class="param-type">: ' + esc(p.type) + '</span>';
            }).join(', ');
        } else {
            paramsHtml = '<span style="color:var(--text-muted)">none</span>';
        }

        // Build flags tags
        let flagsHtml = '';
        if (fn.flags) {
            flagsHtml = fn.flags.split(', ').filter(Boolean).map(f => {
                const cls = f.toLowerCase();
                return '<span class="fn-tag ' + cls + '">' + esc(f) + '</span>';
            }).join(' ');
        }

        // Return type
        const retHtml = fn.return_type
            ? '<span class="fn-return">' + esc(fn.return_type) + '</span>'
            : '<span style="color:var(--text-muted)">void</span>';

        html += '<tr>' +
            '<td class="col-name" style="font-family:\'Fira Code\',monospace;font-size:11px">' + esc(fn.name) + '</td>' +
            '<td class="fn-params">' + paramsHtml + '</td>' +
            '<td>' + retHtml + '</td>' +
            '<td>' + flagsHtml + '</td>' +
            '</tr>';
    }

    html += '</tbody></table>';
    el.innerHTML = html;
}

function renderError(msg) {
    document.getElementById('results').innerHTML =
        '<div class="empty-state" style="color:var(--red)">' + esc(msg) + '</div>';
    document.getElementById('results-info').style.display = 'none';
}

/* ── Helpers ──────────────────────────────────────────────────────────────── */

function isDrillableType(type, value) {
    if (type === 'ObjectProperty' || type === 'ClassProperty' || type === 'StructProperty') {
        // Don't drill into nil/error values
        if (!value || value === 'nil' || value.startsWith('ERROR:')) return false;
        return true;
    }
    return false;
}

function getValueClass(type, value) {
    if (!value) return '';
    if (value.startsWith('ERROR:')) return 'error';

    // Numeric types
    if (type === 'IntProperty' || type === 'Int64Property' || type === 'FloatProperty' ||
        type === 'ByteProperty' || type === 'Int8Property' || type === 'Int16Property' ||
        type === 'DoubleProperty' || type === 'UInt16Property' || type === 'UInt32Property' ||
        type === 'UInt64Property') {
        return 'numeric';
    }
    // Bool
    if (type === 'BoolProperty') {
        return value === 'true' ? 'bool-true' : 'bool-false';
    }
    // String
    if (type === 'StrProperty' || type === 'NameProperty' || type === 'TextProperty') {
        return 'string-val';
    }
    // Drillable
    if (type === 'ObjectProperty' || type === 'StructProperty' || type === 'ClassProperty') {
        return '';
    }
    return '';
}

function truncate(str, max) {
    if (!str) return '';
    str = String(str);
    return str.length > max ? str.substring(0, max) + '...' : str;
}

function esc(str) {
    if (!str) return '';
    const el = document.createElement('span');
    el.textContent = String(str);
    return el.innerHTML.replace(/'/g, '&#39;').replace(/"/g, '&quot;');
}

function setStatus(msg, type) {
    const el = document.getElementById('status-text');
    el.textContent = msg;
    el.className = type ? 'status-' + type : '';
}

/* ── Keyboard shortcuts ───────────────────────────────────────────────────── */

document.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.target.tagName === 'INPUT')) {
        doDump();
    }
});

/* ── Getting-Started Guide ───────────────────────────────────────────────── */

function buildGuideHTML() {
    return '<div class="explorer-guide">' +
        '<h2>UObject Property Explorer</h2>' +
        '<p>This tool lets you browse live game data from the running Palworld server. ' +
        'It reads UObject properties directly from memory via the UE4SS mod.</p>' +

        /* Auto-Discovery */
        '<div class="explorer-guide-section">' +
            '<h3>Auto-Discovery (Recommended)</h3>' +
            '<div class="explorer-steps">' +
                '<div class="explorer-step">' +
                    '<div class="explorer-step-num">1</div>' +
                    '<div class="explorer-step-text"><strong>Click &ldquo;Probe&rdquo;</strong> above. ' +
                    'This automatically scans PalPlayerState and its sub-objects to find property names ' +
                    'for player level, HP, inventory, pals, and stats. No manual browsing needed &mdash; ' +
                    'the system discovers the right properties itself.</div>' +
                '</div>' +
                '<div class="explorer-step">' +
                    '<div class="explorer-step-num">2</div>' +
                    '<div class="explorer-step-text"><strong>Check the results</strong> in the ' +
                    'Auto-Discovery panel. Green values = found, red = not found. ' +
                    'The Live Editor dashboard will use these discovered names automatically ' +
                    'to show player stats, HP, inventory, and pals.</div>' +
                '</div>' +
            '</div>' +
            '<div class="explorer-hint" style="margin:8px 0 0 0">' +
                '<strong>Prerequisite:</strong> the Palworld server must be running with MOD enabled, ' +
                'and at least one player must be connected (so PalPlayerState instances exist).' +
            '</div>' +
        '</div>' +

        /* Manual Exploration */
        '<div class="explorer-guide-section">' +
            '<h3>Manual Exploration (Advanced)</h3>' +
            '<p style="font-size:11px;color:var(--text-sec);margin-bottom:8px">' +
            'Use Dump Properties for deep-diving into any UObject class. ' +
            'Useful for discovering properties that auto-discovery does not cover.</p>' +
            '<div class="explorer-steps">' +
                '<div class="explorer-step">' +
                    '<div class="explorer-step-num">1</div>' +
                    '<div class="explorer-step-text"><strong>Choose a class</strong> from the preset buttons, ' +
                    'or type your own class name.</div>' +
                '</div>' +
                '<div class="explorer-step">' +
                    '<div class="explorer-step-num">2</div>' +
                    '<div class="explorer-step-text"><strong>Click &ldquo;Dump Properties&rdquo;</strong> to fetch all properties ' +
                    'for that class from the live server.</div>' +
                '</div>' +
                '<div class="explorer-step">' +
                    '<div class="explorer-step-num">3</div>' +
                    '<div class="explorer-step-text"><strong>Browse the results.</strong> Values shown in ' +
                    '<span style="color:var(--cyan)">cyan</span> (ObjectProperty, StructProperty) can be ' +
                    '<strong>drilled into</strong> &mdash; click them to explore nested data.</div>' +
                '</div>' +
                '<div class="explorer-step">' +
                    '<div class="explorer-step-num">4</div>' +
                    '<div class="explorer-step-text"><strong>Use the breadcrumb bar</strong> above the results to navigate ' +
                    'back to previous levels.</div>' +
                '</div>' +
            '</div>' +
        '</div>' +

        /* Preset Classes */
        '<div class="explorer-guide-section">' +
            '<h3>Preset Classes</h3>' +
            '<div class="explorer-preset-list">' +
                '<div class="explorer-preset-item"><code>PalPlayerState</code> ' +
                    '<span>Player data: name, level, stats, inventory references</span></div>' +
                '<div class="explorer-preset-item"><code>PalPlayerCharacter</code> ' +
                    '<span>Character in the world: position, pawn, components</span></div>' +
                '<div class="explorer-preset-item"><code>PalGameStateInGame</code> ' +
                    '<span>Current game session: time, weather, world state</span></div>' +
                '<div class="explorer-preset-item"><code>PalWorldSettings</code> ' +
                    '<span>Server configuration values</span></div>' +
            '</div>' +
        '</div>' +

        /* Value Colour Legend */
        '<div class="explorer-guide-section">' +
            '<h3>Value Colour Legend</h3>' +
            '<div class="explorer-legend">' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#34D399"></div>' +
                    '<div class="explorer-legend-label">Numeric values (int, float, byte)</div>' +
                '</div>' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#34D399"></div>' +
                    '<div class="explorer-legend-label">Boolean &mdash; true</div>' +
                '</div>' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#F87171"></div>' +
                    '<div class="explorer-legend-label">Boolean &mdash; false</div>' +
                '</div>' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#FBBF24"></div>' +
                    '<div class="explorer-legend-label">String / name / text</div>' +
                '</div>' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#22D3EE"></div>' +
                    '<div class="explorer-legend-label">Object / struct (drillable)</div>' +
                '</div>' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#A78BFA"></div>' +
                    '<div class="explorer-legend-label">Type column (property type)</div>' +
                '</div>' +
                '<div class="explorer-legend-item">' +
                    '<div class="explorer-legend-swatch" style="background:#F87171"></div>' +
                    '<div class="explorer-legend-label">Error reading value</div>' +
                '</div>' +
            '</div>' +
        '</div>' +

        /* Tips */
        '<div class="explorer-guide-section">' +
            '<h3>Tips</h3>' +
            '<ul class="explorer-tips">' +
                '<li><strong>Auto-discovery</strong> is the fastest way to get started &mdash; ' +
                'just click Probe and the system maps property names automatically.</li>' +
                '<li>The <strong>Instance #</strong> field lets you switch between multiple instances of the ' +
                'same class (e.g. different connected players). Start at 0 for the first.</li>' +
                '<li>Use <strong>Property Path</strong> to jump directly to a nested property without drilling ' +
                'step by step (e.g. <code style="font-family:\'Fira Code\',monospace;font-size:10px;color:var(--cyan)">' +
                'PawnPrivate.SomeComponent</code>).</li>' +
                '<li><strong>Max Items</strong> limits how many properties are returned per request. ' +
                'Increase it if you suspect properties are being cut off.</li>' +
                '<li>Press <strong>Enter</strong> in any input field to trigger a dump without clicking the button.</li>' +
            '</ul>' +
        '</div>' +

    '</div>';
}

function showExplorerGuide() {
    document.getElementById('results').innerHTML = buildGuideHTML();
    document.getElementById('results-info').style.display = 'none';
}

/* ── Load saved discovery log ─────────────────────────────────────────────── */

async function loadSavedDiscoveryLog() {
    try {
        const res = await fetch('/api/discovery-log');
        const data = await res.json();
        if (data && data.properties && !data.error) {
            explorerState.probeResult = data;
            renderProbePanel(data);
            const ts = data.timestamp ? ' (saved ' + data.timestamp + ')' : '';
            setStatus('Loaded previous discovery results' + ts, 'ok');
        }
    } catch (e) {
        // No saved log — that's fine, user needs to probe first
    }
}

/* ── Initialisation ──────────────────────────────────────────────────────── */

showExplorerGuide();
loadSavedDiscoveryLog();
