from __future__ import annotations

import json
import os

from starlette.responses import HTMLResponse


def dashboard_enabled() -> bool:
    value = os.getenv("SMART_ROUTER_DASHBOARD_ENABLED", "true")
    return value.strip().lower() in {"1", "true", "yes", "on"}


def dashboard_response(*, version: str) -> HTMLResponse:
    safe_version = json.dumps(str(version))
    return HTMLResponse(
        _TEMPLATE.replace("__HERMES_VERSION_JSON__", safe_version),
        headers={"Cache-Control": "no-store"},
    )


_TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>Hermes Smart Router dashboard</title>
<style>
:root { font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; background: #0b1020; color: #edf2ff; }
main { width: min(1180px, calc(100% - 28px)); margin: 0 auto; padding: 28px 0 48px; }
header { display:flex; gap:18px; align-items:flex-start; justify-content:space-between; margin-bottom:22px; flex-wrap:wrap; }
h1 { margin:0; font-size:clamp(1.55rem, 3vw, 2.25rem); letter-spacing:-.03em; }
.sub { color:#a9b7d2; margin-top:6px; max-width:760px; line-height:1.45; }
.controls { display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
select, button, input { background:#151d32; color:#edf2ff; border:1px solid #2c3958; border-radius:10px; padding:9px 11px; }
input { min-width:180px; }
.grid { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:12px; }
.card { background:#11182a; border:1px solid #232e48; border-radius:15px; padding:17px; min-height:116px; }
.label { color:#91a0bd; font-size:.78rem; text-transform:uppercase; letter-spacing:.08em; }
.value { margin-top:9px; font-size:1.65rem; font-weight:750; letter-spacing:-.035em; }
.small { color:#9eabc4; margin-top:6px; font-size:.82rem; line-height:1.35; }
.section { margin-top:14px; display:grid; grid-template-columns:1.2fr .8fr; gap:12px; }
.panel { background:#11182a; border:1px solid #232e48; border-radius:15px; padding:18px; }
.panel h2 { font-size:1rem; margin:0 0 14px; }
.bar-row { display:grid; grid-template-columns:78px 1fr 52px; gap:10px; align-items:center; margin:12px 0; }
.track { height:12px; border-radius:99px; background:#202a42; overflow:hidden; }
.fill { height:100%; border-radius:99px; background:linear-gradient(90deg,#73a5ff,#8fe3cf); min-width:0; }
.notice { margin-top:14px; border:1px solid #3c4660; border-radius:12px; padding:12px 14px; color:#bdc9df; background:#101728; line-height:1.45; }
.notice.warn { border-color:#715d31; color:#f1d79a; }
.meta { margin-top:14px; color:#8493af; font-size:.78rem; line-height:1.55; }
code { background:#172035; padding:2px 5px; border-radius:5px; }
@media(max-width:900px) { .grid {grid-template-columns:repeat(2,minmax(0,1fr));} .section{grid-template-columns:1fr;} }
@media(max-width:520px) { .grid {grid-template-columns:1fr;} }
</style>
</head>
<body>
<main>
<header>
  <div>
    <h1>Hermes Smart Router</h1>
    <div class="sub">Measured token and USD routing telemetry. Cost savings use a same-token strong-only counterfactual; output-token reduction is shown only as an enforced budget-cap delta.</div>
  </div>
  <div class="controls">
    <input id="apiKey" type="password" autocomplete="off" placeholder="API key (if required)">
    <button id="saveKey">Use key</button>
    <select id="hours"><option value="1">1 hour</option><option value="24" selected>24 hours</option><option value="168">7 days</option><option value="720">30 days</option></select>
    <button id="refresh">Refresh</button>
  </div>
</header>
<div class="grid">
  <div class="card"><div class="label">Routed requests</div><div class="value" id="requests">—</div><div class="small" id="usageCoverage">Usage coverage —</div></div>
  <div class="card"><div class="label">Measured tokens</div><div class="value" id="tokens">—</div><div class="small" id="tokenSplit">Input — · Output —</div></div>
  <div class="card"><div class="label">Measured cost</div><div class="value" id="cost">—</div><div class="small" id="costCoverage">Pricing coverage —</div></div>
  <div class="card"><div class="label">Savings vs strong</div><div class="value" id="savings">—</div><div class="small" id="savingsUsd">Same-token baseline</div></div>
  <div class="card"><div class="label">Strong-only baseline</div><div class="value" id="baseline">—</div><div class="small">Same measured token counts priced at the strong tier.</div></div>
  <div class="card"><div class="label">Output budget reduction</div><div class="value" id="budget">—</div><div class="small">Cap delta only; not claimed as generated-token savings.</div></div>
  <div class="card"><div class="label">Streaming requests</div><div class="value" id="streaming">—</div><div class="small">Streaming usage may be absent depending on the upstream.</div></div>
  <div class="card"><div class="label">Version</div><div class="value">v<span id="version"></span></div><div class="small">Built into Smart Router at <code>/dashboard</code>.</div></div>
</div>
<div class="section">
  <section class="panel"><h2>Tier mix</h2><div id="tiers"></div></section>
  <section class="panel"><h2>Measurement quality</h2><div id="notice" class="notice">Loading…</div><div class="meta" id="meta"></div></section>
</div>
</main>
<script>
const VERSION = __HERMES_VERSION_JSON__;
const fmtInt = n => new Intl.NumberFormat().format(Number(n || 0));
const fmtUsd = n => '$' + Number(n || 0).toFixed(Number(n || 0) < 1 ? 4 : 2);
const fmtPct = n => n == null ? 'N/A' : (Number(n) * 100).toFixed(1) + '%';
function setText(id, value) { document.getElementById(id).textContent = value; }
async function load() {
  const hours = document.getElementById('hours').value;
  const key = sessionStorage.getItem('hermesDashboardKey') || '';
  const headers = key ? {'Authorization':'Bearer ' + key} : {};
  const response = await fetch('/dashboard/api/summary?hours=' + encodeURIComponent(hours), {cache:'no-store', headers});
  if (!response.ok) throw new Error(response.status === 401 ? 'API key required or invalid' : 'dashboard API returned ' + response.status);
  const d = await response.json();
  setText('version', VERSION);
  setText('requests', fmtInt(d.requests));
  setText('usageCoverage', 'Usage coverage ' + fmtPct(d.usage_coverage));
  setText('tokens', fmtInt(d.total_tokens));
  setText('tokenSplit', 'Input ' + fmtInt(d.input_tokens) + ' · Output ' + fmtInt(d.output_tokens));
  setText('cost', d.priced_requests ? fmtUsd(d.actual_cost_usd) : 'N/A');
  setText('costCoverage', 'Pricing coverage ' + fmtPct(d.cost_coverage));
  setText('savings', d.savings_pct == null ? 'N/A' : fmtPct(d.savings_pct));
  setText('savingsUsd', d.priced_requests ? fmtUsd(d.savings_usd) + ' measured saving' : 'Configure tier pricing to calculate USD');
  setText('baseline', d.priced_requests ? fmtUsd(d.strong_same_token_cost_usd) : 'N/A');
  setText('budget', fmtInt(d.budget_tokens_avoided));
  setText('streaming', fmtInt(d.streaming_requests));
  const total = Math.max(1, Object.values(d.tier_counts || {}).reduce((a,b)=>a+Number(b),0));
  document.getElementById('tiers').innerHTML = ['fast','standard','strong'].map(t => {
    const n = Number((d.tier_counts || {})[t] || 0); const p = n / total * 100;
    return `<div class="bar-row"><div>${t}</div><div class="track"><div class="fill" style="width:${p.toFixed(2)}%"></div></div><div>${p.toFixed(0)}%</div></div>`;
  }).join('');
  const notice = document.getElementById('notice');
  const warnings = [];
  if (d.error) warnings.push('Cost ledger disabled: ' + d.error);
  if (!d.pricing_configured) warnings.push('No complete USD tier pricing is configured. Token totals are real, but USD savings are unavailable.');
  if (d.requests && d.usage_coverage < .95) warnings.push('Usage coverage is below 95%; do not treat the displayed cost as the complete bill.');
  if (!warnings.length) warnings.push('Measurement coverage is healthy for this window. USD values use measured upstream usage only.');
  notice.textContent = warnings.join(' ');
  notice.className = warnings.length && (d.error || !d.pricing_configured || d.usage_coverage < .95) ? 'notice warn' : 'notice';
  setText('meta', `Baseline: ${d.cost_baseline} · Token reduction: ${d.token_reduction_kind} · Pricing: ${d.pricing_source || 'not configured'}`);
}
function showError(e) { document.getElementById('notice').textContent = String(e); document.getElementById('notice').className='notice warn'; }
document.getElementById('saveKey').addEventListener('click', () => { sessionStorage.setItem('hermesDashboardKey', document.getElementById('apiKey').value.trim()); load().catch(showError); });
document.getElementById('apiKey').value = sessionStorage.getItem('hermesDashboardKey') || '';
document.getElementById('refresh').addEventListener('click', () => load().catch(showError));
document.getElementById('hours').addEventListener('change', () => load().catch(showError));
load().catch(showError);
setInterval(() => load().catch(()=>{}), 30000);
</script>
</body>
</html>'''
