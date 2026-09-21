const $token = document.getElementById("token");
const $msg = document.getElementById("msg");

chrome.storage.local.get("token").then(({ token }) => {
  if (token) $token.value = token;
});

document.getElementById("save").onclick = async () => {
  const token = $token.value.trim();
  $msg.className = "msg";
  $msg.textContent = "测试中…";
  try {
    const res = await fetch("http://127.0.0.1:48787/api/bridge/status", {
      headers: { "Authorization": "Bearer " + token },
    });
    if (res.status === 401) throw new Error("令牌无效");
    if (!res.ok) throw new Error("连接异常 " + res.status);
    await chrome.storage.local.set({ token });
    $msg.className = "msg ok";
    $msg.textContent = "✓ 配对成功";
  } catch (e) {
    $msg.className = "msg err";
    $msg.textContent = e.message.includes("Failed to fetch")
      ? "无法连接：请确认简密 App 正在运行" : e.message;
  }
};
