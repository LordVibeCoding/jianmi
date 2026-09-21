// 简密扩展 · 内容脚本：把凭证填进页面表单
// 兼容 React/Vue 等受控组件（走原生 setter + input/change 事件）
(() => {
  function setValue(el, value) {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, "value").set;
    setter.call(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function visible(el) {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function findFields() {
    const pw = [...document.querySelectorAll('input[type="password"]')]
      .find(visible);
    let user = null;
    if (pw && pw.form) {
      // 同一表单里，密码框之前最近的文本框
      const inputs = [...pw.form.querySelectorAll(
        'input[type="text"], input[type="email"], input[type="tel"], input:not([type])')]
        .filter(visible);
      user = inputs.reverse().find(i =>
        i.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING);
    }
    if (!user) {
      user = [...document.querySelectorAll(
        'input[autocomplete="username"], input[type="email"], input[name*="user" i], input[name*="email" i], input[id*="user" i], input[id*="email" i]')]
        .find(visible);
    }
    return { user, pw };
  }

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg.type !== "jianmi-fill") return;
    const { user, pw } = findFields();
    if (msg.username && user) setValue(user, msg.username);
    if (msg.password && pw) setValue(pw, msg.password);
    sendResponse({ filled: { username: !!(msg.username && user),
                             password: !!(msg.password && pw) } });
  });
})();
