// 简密扩展 · 后台：实时上报当前标签页给本地 App
// → ⌥⌘N 快速捕获零权限预填网址（替代 AppleScript 自动化）
const BASE = "http://127.0.0.1:48787";

async function getToken() {
  const { token } = await chrome.storage.local.get("token");
  return token || "";
}

async function reportTab(tab) {
  try {
    if (!tab || !tab.url || !/^https?:/.test(tab.url)) return;
    const token = await getToken();
    if (!token) return;
    await fetch(BASE + "/api/bridge/tab", {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ url: tab.url, title: tab.title || "" }),
    });
  } catch (_) { /* App 未运行时静默 */ }
}

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  try { reportTab(await chrome.tabs.get(tabId)); } catch (_) {}
});

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  if (change.status === "complete" && tab.active) reportTab(tab);
});

chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  try {
    const [tab] = await chrome.tabs.query({ active: true, windowId });
    reportTab(tab);
  } catch (_) {}
});
