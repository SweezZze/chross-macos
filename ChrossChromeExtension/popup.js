const BASE_URL = "http://127.0.0.1:52847";

// DOM Elements
const statusPill = document.getElementById("statusPill");
const activateAppBtn = document.getElementById("activateAppBtn");
const offlineView = document.getElementById("offlineView");
const connectedView = document.getElementById("connectedView");
const retryBtn = document.getElementById("retryBtn");

const todayHoursEl = document.getElementById("todayHours");
const todayProgressBar = document.getElementById("todayProgressBar");
const todayGoalEl = document.getElementById("todayGoal");

const runningSessionSection = document.getElementById("runningSessionSection");
const idleSessionSection = document.getElementById("idleSessionSection");

const runningProjectNameEl = document.getElementById("runningProjectName");
const timerEl = document.getElementById("timer");
const pauseBtn = document.getElementById("pauseBtn");
const pauseIcon = document.getElementById("pauseIcon");
const pauseLabel = document.getElementById("pauseLabel");
const stopBtn = document.getElementById("stopBtn");

const projectNameInput = document.getElementById("projectNameInput");
const presetsGroup = document.getElementById("presetsGroup");
const presetSelect = document.getElementById("presetSelect");
const includeCurrentSiteCheck = document.getElementById("includeCurrentSiteCheck");
const startBtn = document.getElementById("startBtn");

const currentDomainBadge = document.getElementById("currentDomainBadge");
const currentDomainTitle = document.getElementById("currentDomainTitle");
const currentDomainStatus = document.getElementById("currentDomainStatus");
const toggleCurrentSiteBtn = document.getElementById("toggleCurrentSiteBtn");

const sitesCount = document.getElementById("sitesCount");
const sitesList = document.getElementById("sitesList");
const sitesEmpty = document.getElementById("sitesEmpty");

// State
let timerInterval = null;
let pollInterval = null;
let currentStatus = null;
let baseElapsedSeconds = 0;
let baseElapsedAtMs = 0;
let currentTabURL = null;
let currentTabDomain = null;

// Normalize URL into domain (like DomainNormalizer in Swift)
function extractDomain(urlString) {
  if (!urlString) return null;
  try {
    const url = new URL(urlString.startsWith("http") ? urlString : `https://${urlString}`);
    let host = url.hostname.toLowerCase();
    if (host.startsWith("www.")) {
      host = host.slice(4);
    }
    return host;
  } catch {
    return null;
  }
}

// Format duration HH:MM:SS
function formatDuration(totalSeconds) {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const h = String(Math.floor(seconds / 3600)).padStart(2, "0");
  const m = String(Math.floor((seconds % 3600) / 60)).padStart(2, "0");
  const s = String(seconds % 60).padStart(2, "0");
  return `${h}:${m}:${s}`;
}

// Format today's hours (e.g. "3 h 42")
function formatHours(totalSeconds) {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(seconds / 3600);
  const m = String(Math.floor((seconds % 3600) / 60)).padStart(2, "0");
  return `${h} h ${m}`;
}

// Timer management
function startTimer(elapsedSeconds, isPaused) {
  baseElapsedSeconds = elapsedSeconds;
  baseElapsedAtMs = Date.now();
  stopTimer();
  tickTimer(isPaused);
  if (!isPaused) {
    timerInterval = setInterval(() => tickTimer(false), 1000);
  }
}

function stopTimer() {
  if (timerInterval) {
    clearInterval(timerInterval);
    timerInterval = null;
  }
}

function tickTimer(isPaused) {
  if (isPaused) {
    timerEl.textContent = formatDuration(baseElapsedSeconds);
    return;
  }
  const live = baseElapsedSeconds + (Date.now() - baseElapsedAtMs) / 1000;
  timerEl.textContent = formatDuration(live);
}

// API Calls
async function apiCall(path, method = "GET", body = null) {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 1500);
    const options = {
      method,
      signal: controller.signal,
      headers: { "Content-Type": "application/json" },
    };
    if (body) {
      options.body = JSON.stringify(body);
    }
    const res = await fetch(`${BASE_URL}${path}`, options);
    clearTimeout(timeoutId);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

// Notify background service worker to sync badge
function notifyBackgroundBadge() {
  chrome.runtime.sendMessage({ action: "refreshBadge" }, () => {
    // Ignore runtime lastError if background worker was sleeping
    if (chrome.runtime.lastError) {}
  });
}

// Detect current active tab in Chrome
async function detectCurrentTab() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab && tab.url && !tab.url.startsWith("chrome://") && !tab.url.startsWith("chrome-extension://")) {
      currentTabURL = tab.url;
      currentTabDomain = extractDomain(tab.url);
    } else {
      currentTabURL = null;
      currentTabDomain = null;
    }
  } catch {
    currentTabURL = null;
    currentTabDomain = null;
  }
}

// Render UI based on Chross status
function render(status) {
  currentStatus = status;

  if (!status) {
    // OFFLINE
    offlineView.hidden = false;
    connectedView.hidden = true;
    statusPill.className = "status-pill status-offline";
    statusPill.textContent = "Déconnecté";
    stopTimer();
    return;
  }

  // CONNECTED
  offlineView.hidden = true;
  connectedView.hidden = false;

  // Header status pill
  if (status.isRunning) {
    if (status.isPaused) {
      statusPill.className = "status-pill status-paused";
      statusPill.textContent = "En pause";
    } else if (status.isOutOfScope) {
      statusPill.className = "status-pill status-ready";
      statusPill.textContent = "Hors sélection";
    } else {
      statusPill.className = "status-pill status-running";
      statusPill.textContent = "En cours";
    }
  } else {
    statusPill.className = "status-pill status-ready";
    statusPill.textContent = "Prêt";
  }

  // Today Progress Bar
  const todaySeconds = status.todaySeconds || 0;
  const goalHours = status.dailyGoalHours || 7;
  const goalSeconds = goalHours * 3600;
  const fraction = goalSeconds > 0 ? Math.min(1, todaySeconds / goalSeconds) : 0;

  todayHoursEl.textContent = formatHours(todaySeconds);
  todayProgressBar.style.width = `${Math.round(fraction * 100)}%`;
  todayGoalEl.textContent = `Objectif ${goalHours}h`;

  // Presets dropdown
  const presets = status.presets || [];
  if (presets.length > 0) {
    presetsGroup.hidden = false;
    const currentSelected = presetSelect.value;
    presetSelect.innerHTML = '<option value="">(Projet libre)</option>';
    presets.forEach((presetName) => {
      const opt = document.createElement("option");
      opt.value = presetName;
      opt.textContent = presetName;
      presetSelect.appendChild(opt);
    });
    presetSelect.value = currentSelected;
  } else {
    presetsGroup.hidden = true;
  }

  // Session Running vs Idle
  if (status.isRunning) {
    runningSessionSection.hidden = false;
    idleSessionSection.hidden = true;

    runningProjectNameEl.textContent = status.projectName || "Session en cours";

    // Pause / Resume button state
    if (status.isPaused) {
      pauseIcon.textContent = "▶";
      pauseLabel.textContent = "Reprendre";
      pauseBtn.classList.remove("btn-secondary");
      pauseBtn.classList.add("btn-accent");
    } else {
      pauseIcon.textContent = "⏸";
      pauseLabel.textContent = "Pause";
      pauseBtn.classList.add("btn-secondary");
      pauseBtn.classList.remove("btn-accent");
    }

    startTimer(status.elapsedSeconds || 0, status.isPaused);
  } else {
    runningSessionSection.hidden = true;
    idleSessionSection.hidden = false;
    stopTimer();
    timerEl.textContent = "00:00:00";
  }

  // Current Tab Inspection
  updateCurrentTabCard(status);

  // Sites list
  const sites = status.sites || [];
  sitesCount.textContent = sites.length;
  sitesList.innerHTML = "";

  if (sites.length === 0) {
    sitesEmpty.hidden = false;
  } else {
    sitesEmpty.hidden = true;
    sites.forEach((site) => {
      const li = document.createElement("li");

      const span = document.createElement("span");
      span.className = "site-item-name";
      span.textContent = site.displayName || site.key;

      const delBtn = document.createElement("button");
      delBtn.className = "site-remove-btn";
      delBtn.textContent = "✕";
      delBtn.title = `Retirer ${site.displayName} de la session`;
      delBtn.addEventListener("click", () => removeSite(site.key));

      li.appendChild(span);
      li.appendChild(delBtn);
      sitesList.appendChild(li);
    });
  }
}

// Update the Current Tab Inspection card
function updateCurrentTabCard(status) {
  if (!currentTabDomain) {
    currentDomainTitle.textContent = "Aucun onglet web actif";
    currentDomainBadge.textContent = "—";
    currentDomainStatus.textContent = "Page système ou vide";
    currentDomainStatus.className = "domain-substatus";
    toggleCurrentSiteBtn.disabled = true;
    toggleCurrentSiteBtn.textContent = "+ Ajouter";
    return;
  }

  currentDomainBadge.textContent = "WEB";
  currentDomainTitle.textContent = currentTabDomain;

  const sites = status?.sites || [];
  const isDeclared = sites.some(
    (s) => s.key === currentTabDomain || currentTabDomain.endsWith(`.${s.key}`)
  );

  toggleCurrentSiteBtn.disabled = !status?.isRunning;

  if (isDeclared) {
    currentDomainStatus.textContent = "✓ Suivi dans la session";
    currentDomainStatus.className = "domain-substatus is-tracked";
    toggleCurrentSiteBtn.textContent = "Retirer";
    toggleCurrentSiteBtn.className = "btn btn-sm btn-secondary";
  } else {
    currentDomainStatus.textContent = status?.isRunning
      ? (status.declaredWebsitesCount === 0 ? "Comptabilisé (session globale)" : "Non inclus dans la sélection")
      : "Prêt à être ajouté";
    currentDomainStatus.className = "domain-substatus";
    toggleCurrentSiteBtn.textContent = "+ Ajouter";
    toggleCurrentSiteBtn.className = "btn btn-sm btn-accent";
  }
}

// Actions
async function refresh() {
  const status = await apiCall("/status");
  render(status);
  notifyBackgroundBadge();
}

async function startSession() {
  let projectName = projectNameInput.value.trim();
  const selectedPreset = presetSelect.value;

  if (!projectName && selectedPreset) {
    projectName = selectedPreset;
  }
  if (!projectName) {
    projectName = currentTabDomain ? `Projet ${currentTabDomain}` : "Session Chrome";
  }

  startBtn.disabled = true;
  try {
    const payload = {
      projectName,
      presetName: selectedPreset || undefined,
    };
    const res = await apiCall("/session/start", "POST", payload);
    if (res && includeCurrentSiteCheck.checked && currentTabURL) {
      await apiCall("/session/sites", "POST", { url: currentTabURL });
    }
  } finally {
    startBtn.disabled = false;
  }
  await refresh();
}

async function togglePause() {
  pauseBtn.disabled = true;
  try {
    await apiCall("/session/toggle-pause", "POST");
  } finally {
    pauseBtn.disabled = false;
  }
  await refresh();
}

async function stopSession() {
  stopBtn.disabled = true;
  try {
    await apiCall("/session/stop", "POST");
  } finally {
    stopBtn.disabled = false;
  }
  await refresh();
}

async function toggleCurrentSite() {
  if (!currentTabURL || !currentTabDomain || !currentStatus) return;

  toggleCurrentSiteBtn.disabled = true;
  const sites = currentStatus.sites || [];
  const isDeclared = sites.some(
    (s) => s.key === currentTabDomain || currentTabDomain.endsWith(`.${s.key}`)
  );

  try {
    if (isDeclared) {
      await apiCall("/session/sites/remove", "POST", { key: currentTabDomain });
    } else {
      await apiCall("/session/sites", "POST", { url: currentTabURL });
    }
  } finally {
    toggleCurrentSiteBtn.disabled = false;
  }
  await refresh();
}

async function removeSite(key) {
  await apiCall("/session/sites/remove", "POST", { key });
  await refresh();
}

async function activateMacApp() {
  await apiCall("/activate-app", "POST");
}

// Event Listeners
startBtn.addEventListener("click", startSession);
pauseBtn.addEventListener("click", togglePause);
stopBtn.addEventListener("click", stopSession);
retryBtn.addEventListener("click", refresh);
activateAppBtn.addEventListener("click", activateMacApp);
toggleCurrentSiteBtn.addEventListener("click", toggleCurrentSite);

projectNameInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    startSession();
  }
});

presetSelect.addEventListener("change", () => {
  if (presetSelect.value) {
    projectNameInput.value = presetSelect.value;
  }
});

// Initialization
async function init() {
  await detectCurrentTab();
  await refresh();

  // Refresh every 3 seconds while popup is open
  pollInterval = setInterval(refresh, 3000);
}

document.addEventListener("DOMContentLoaded", init);
