/* ── UObject Explorer — LiveEditor Dev Tool ──────────────────────────────── */

const explorerState = {
    className: 'PalPlayerState',
    instanceIndex: 0,
    propertyPath: '',
    maxItems: 50,
    lastResult: null,
    history: [],     // breadcrumb trail: [{ className, instanceIndex, propertyPath }]
    loading: false,
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

/* ── Main Dump ────────────────────────────────────────────────────────────── */

async function doDump() {
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

    let html = '<table><thead><tr>' +
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
