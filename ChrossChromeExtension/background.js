const BASE_URL = "http://127.0.0.1:52847";

// Helper: Format elapsed seconds for the badge (e.g. "5m", "42m", "1h15")
function formatBadgeText(seconds) {
  if (seconds <= 0) return "";
  const totalMinutes = Math.floor(seconds / 60);
  if (totalMinutes < 60) {
    return `${totalMinutes}m`;
  }
  const hours = Math.floor(totalMinutes / 60);
  const remainingMinutes = totalMinutes % 60;
  if (hours < 10) {
    return `${hours}h${String(remainingMinutes).padStart(2, "0")}`;
  }
  return `${hours}h`;
}

// Fetch status from the macOS Chross local server
async function fetchStatus() {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 1200);
    const res = await fetch(`${BASE_URL}/status`, { signal: controller.signal });
    clearTimeout(timeoutId);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

// Update the extension toolbar badge and tooltip
async function updateBadge(status) {
  if (!status) {
    // Offline / App not running
    await chrome.action.setBadgeText({ text: "" });
    await chrome.action.setTitle({ title: "Chross : App déconnectée" });
    return;
  }

  if (status.isRunning) {
    if (status.isPaused) {
      await chrome.action.setBadgeText({ text: "II" });
      await chrome.action.setBadgeBackgroundColor({ color: "#FF9500" });
      await chrome.action.setBadgeTextColor({ color: "#FFFFFF" }).catch(() => {});
      await chrome.action.setTitle({
        title: `Chross : ${status.projectName || "Session"} (En pause)`,
      });
    } else {
      const text = formatBadgeText(status.elapsedSeconds || 0);
      await chrome.action.setBadgeText({ text: text || "ON" });
      await chrome.action.setBadgeBackgroundColor({ color: "#D6FF3F" });
      await chrome.action.setBadgeTextColor({ color: "#000000" }).catch(() => {});
      await chrome.action.setTitle({
        title: `Chross : ${status.projectName || "Session"} (En cours)`,
      });
    }
  } else {
    await chrome.action.setBadgeText({ text: "" });
    await chrome.action.setTitle({ title: "Chross : Prêt" });
  }
}

// Setup Context Menus
function setupContextMenus() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "chross-add-site",
      title: "Ajouter ce site à la session Chross",
      contexts: ["page", "link"],
    });

    chrome.contextMenus.create({
      id: "chross-toggle-timer",
      title: "Démarrer / Mettre en pause Chross",
      contexts: ["action", "page"],
    });
  });
}

// Handle Context Menu clicks
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === "chross-add-site") {
    const url = info.linkUrl || info.pageUrl || tab?.url;
    if (url) {
      try {
        await fetch(`${BASE_URL}/session/sites`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ url }),
        });
        const status = await fetchStatus();
        await updateBadge(status);
      } catch (err) {
        console.error("Impossible d'ajouter le site:", err);
      }
    }
  } else if (info.menuItemId === "chross-toggle-timer") {
    try {
      const status = await fetchStatus();
      if (status && status.isRunning) {
        await fetch(`${BASE_URL}/session/toggle-pause`, { method: "POST" });
      } else {
        await fetch(`${BASE_URL}/session/start`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ projectName: "Session Chrome" }),
        });
      }
      const newStatus = await fetchStatus();
      await updateBadge(newStatus);
    } catch (err) {
      console.error("Erreur toggle timer:", err);
    }
  }
});

// Handle keyboard shortcuts defined in manifest.json
chrome.commands.onCommand.addListener(async (command) => {
  if (command === "toggle-pause") {
    try {
      const status = await fetchStatus();
      if (status && status.isRunning) {
        await fetch(`${BASE_URL}/session/toggle-pause`, { method: "POST" });
      } else {
        await fetch(`${BASE_URL}/session/start`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ projectName: "Session Chrome" }),
        });
      }
      const updated = await fetchStatus();
      await updateBadge(updated);
    } catch (e) {
      console.error("Erreur commande toggle-pause:", e);
    }
  } else if (command === "add-current-site") {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab?.url) {
      try {
        await fetch(`${BASE_URL}/session/sites`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ url: tab.url }),
        });
        const updated = await fetchStatus();
        await updateBadge(updated);
      } catch (e) {
        console.error("Erreur commande add-current-site:", e);
      }
    }
  }
});

// Message listener from popup
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.action === "refreshBadge") {
    fetchStatus().then((status) => {
      updateBadge(status);
      sendResponse({ success: true, status });
    });
    return true; // Keep message channel open for async response
  }
});

// Periodic background sync using chrome.alarms (runs every 1 min)
chrome.alarms.create("chross-sync", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === "chross-sync") {
    const status = await fetchStatus();
    await updateBadge(status);
  }
});

// Refresh badge when switching tabs or window focus
chrome.tabs.onActivated.addListener(async () => {
  const status = await fetchStatus();
  await updateBadge(status);
});

// Initial boot
chrome.runtime.onInstalled.addListener(() => {
  setupContextMenus();
  fetchStatus().then(updateBadge);
});

chrome.runtime.onStartup.addListener(() => {
  setupContextMenus();
  fetchStatus().then(updateBadge);
});
