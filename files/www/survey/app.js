"use strict";
// survey-ui frontend. talks only to /cgi-bin/survey-api, which proxies
// kismet and drives the survey cli. no framework, no build step.

const API = "/cgi-bin/survey-api";
const $ = (id) => document.getElementById(id);

const state = {
	running: false,
	busy: false,        // a control action (start/stop) is in flight
	serverTime: 0,      // router epoch from the last devices fetch
	devices: [],
	sort: "sig",
	filter: "",
	window: "300",
	timer: null,
};

// --- helpers ---

async function api(action, opts = {}) {
	const r = await fetch(`${API}?action=${action}${opts.qs || ""}`, {
		method: opts.method || "GET",
		headers: opts.body ? { "Content-Type": "application/x-www-form-urlencoded" } : undefined,
		body: opts.body,
	});
	if (!r.ok) throw new Error(`${action}: ${r.status}`);
	return r;
}

function toast(msg) {
	const t = $("toast");
	t.textContent = msg;
	t.hidden = false;
	clearTimeout(toast._t);
	toast._t = setTimeout(() => { t.hidden = true; }, 3000);
}

function fmtDuration(sec) {
	sec = Math.max(0, Math.floor(sec));
	const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
	if (h) return `${h}h${String(m).padStart(2, "0")}m`;
	if (m) return `${m}m${String(s).padStart(2, "0")}s`;
	return `${s}s`;
}

function fmtAge(sec) {
	if (sec < 0) sec = 0;
	if (sec < 60) return `${Math.floor(sec)}s`;
	if (sec < 3600) return `${Math.floor(sec / 60)}m`;
	return `${Math.floor(sec / 3600)}h`;
}

// map dBm to a 0..100 bar width: -95 -> 0, -30 -> 100
function sigPct(dbm) {
	return Math.max(0, Math.min(100, ((dbm + 95) / 65) * 100));
}
function sigClass(dbm) {
	if (dbm >= -60) return "sig-good";
	if (dbm >= -75) return "sig-mid";
	return "sig-bad";
}

function shortType(t) {
	if (!t) return "";
	return t.replace(/^Wi-Fi\s*/i, "") || t;
}

// --- rendering ---

function renderStatus(st) {
	state.running = !!st.running;
	const pill = $("state-pill");
	pill.textContent = state.running ? (st.mode || "running") : "stopped";
	pill.className = "pill " + (state.running ? "pill-on" : "pill-off");

	$("s-devices").textContent = st.devices != null ? st.devices : "--";
	$("s-uptime").textContent = state.running ? fmtDuration(st.uptime || 0) : "--";
	$("s-gps").textContent = st.gps_fix === true ? "yes" : (state.running ? "no" : "--");
	$("s-log").textContent = st.log_size || "--";

	if (!state.busy) {
		$("btn-start").disabled = state.running;
		$("btn-stop").disabled = !state.running;
		$("mode").disabled = state.running;
	}
}

function renderGps(g) {
	const loc = g["kismet.common.location.geopoint"];
	const fix = g["kismet.common.location.fix"] || 0;
	// kismet reports no satellite count, so survey-api merges gpsd's in:
	// usat = used in the fix, nsat = in view
	const usat = g["survey.gps.usat"], nsat = g["survey.gps.nsat"];
	const card = $("gps-card");
	if (fix >= 2 && Array.isArray(loc) && loc.length === 2) {
		// kismet geopoint is [lon, lat]
		$("gps-lat").textContent = "lat " + loc[1].toFixed(5);
		$("gps-lon").textContent = "lon " + loc[0].toFixed(5);
		$("gps-sats").textContent = (nsat != null ? usat + "/" + nsat : "?") + " sats";
		card.hidden = false;
	} else {
		card.hidden = true;
	}
}

function renderDevices() {
	const box = $("devices");
	const f = state.filter.toLowerCase();

	let list = state.devices.slice();
	if (f) {
		list = list.filter((d) =>
			(d.name || "").toLowerCase().includes(f) ||
			(d.mac || "").toLowerCase().includes(f));
	}

	list.sort((a, b) => {
		if (state.sort === "name") return (a.name || "~").localeCompare(b.name || "~");
		if (state.sort === "seen") return (b.seen || 0) - (a.seen || 0);
		return (b.sig || -999) - (a.sig || -999); // signal, strongest first
	});

	if (!list.length) {
		box.innerHTML = '<p class="empty">' +
			(state.devices.length ? "nothing matches the filter" : "no devices yet") + "</p>";
		return;
	}

	const now = state.serverTime || Math.floor(Date.now() / 1000);
	const rows = list.map((d) => {
		const sig = typeof d.sig === "number" ? d.sig : null;
		const cls = sig != null ? sigClass(sig) : "";
		const pct = sig != null ? sigPct(sig) : 0;
		const sigTxt = sig != null ? `${sig} dBm` : "--";
		// no SSID: every client, plus hidden APs. the vendor is then the most
		// identifying thing we have (an SSID can be hidden, an OUI can't), so lead
		// with it rather than a useless "(hidden)".
		const hidden = !d.name || d.name === d.mac;
		const vendor = d.manuf && d.manuf !== "Unknown" ? d.manuf : "";
		const name = hidden ? (vendor ? esc(vendor) : "(unknown device)") : esc(d.name);
		const chan = d.chan || (d.freq ? Math.round(d.freq / 1000) : "");
		const crypt = d.crypt && d.crypt !== "Open" ? d.crypt : (d.crypt === "Open" ? "open" : "");
		const age = d.seen ? fmtAge(now - d.seen) : "";

		return `<div class="dev ${cls}">
			<div class="dev-top">
				<span class="dev-name${hidden ? " hidden-ssid" : ""}">${name}</span>
				<span class="dev-sig">${sigTxt}</span>
			</div>
			<div class="bar-wrap"><div class="bar-fill" style="width:${pct}%"></div></div>
			<div class="dev-meta">
				<span class="mac">${esc(d.mac || "")}</span>
				${chan ? `<span class="badge">ch ${esc(String(chan))}</span>` : ""}
				${d.type ? `<span class="badge">${esc(shortType(d.type))}</span>` : ""}
				${crypt ? `<span>${esc(crypt)}</span>` : ""}
				${vendor && !hidden ? `<span>${esc(vendor)}</span>` : ""}
				${age ? `<span>${age} ago</span>` : ""}
			</div>
		</div>`;
	});
	box.innerHTML = rows.join("");
}

function esc(s) {
	return String(s).replace(/[&<>"']/g, (c) =>
		({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

// --- polling ---

async function refresh() {
	try {
		const stResp = await api("status");
		renderStatus(await stResp.json());
	} catch (e) {
		toast("status unreachable");
		return;
	}

	if (!state.running) {
		state.devices = [];
		renderDevices();
		$("gps-card").hidden = true;
		stamp();
		return;
	}

	try {
		const dResp = await api("devices", { qs: `&window=${state.window}` });
		const t = dResp.headers.get("X-Server-Time");
		if (t) state.serverTime = parseInt(t, 10);
		state.devices = await dResp.json();
		renderDevices();
	} catch (e) {
		// kismet may still be coming up right after start; leave the last list
	}

	try {
		const gResp = await api("gps");
		renderGps(await gResp.json());
	} catch (e) { /* gps optional */ }

	stamp();
}

function stamp() {
	const d = new Date();
	$("updated").textContent = "updated " + d.toLocaleTimeString();
}

function startPolling() {
	stopPolling();
	refresh();
	state.timer = setInterval(refresh, 4000);
}
function stopPolling() {
	if (state.timer) { clearInterval(state.timer); state.timer = null; }
}

// --- controls ---

async function control(action, qs) {
	state.busy = true;
	$("btn-start").disabled = true;
	$("btn-stop").disabled = true;
	$("mode").disabled = true;
	try {
		const r = await api(action, { method: "POST", qs });
		renderStatus(await r.json());
	} catch (e) {
		toast(`${action} failed`);
	} finally {
		state.busy = false;
		refresh();
	}
}

// --- wire up ---

$("btn-start").onclick = () => control("start", `&mode=${$("mode").value}`);
$("btn-stop").onclick = () => control("stop");

$("filter").oninput = (e) => { state.filter = e.target.value; renderDevices(); };
$("sort").onchange = (e) => { state.sort = e.target.value; renderDevices(); };
$("window").onchange = (e) => { state.window = e.target.value; refresh(); };

$("auto").onchange = (e) => { e.target.checked ? startPolling() : stopPolling(); };

// pause polling when the tab is hidden -- saves battery during a walkabout
document.addEventListener("visibilitychange", () => {
	if (document.hidden) stopPolling();
	else if ($("auto").checked) startPolling();
});

startPolling();
