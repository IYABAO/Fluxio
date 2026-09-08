// options：读写扩展配置
const hostEl = document.getElementById('host');
const tokenEl = document.getElementById('token');
const savedEl = document.getElementById('saved');

chrome.storage.sync.get(['host', 'token'], (cfg) => {
  hostEl.value = cfg.host || 'http://127.0.0.1:8730';
  tokenEl.value = cfg.token || '';
});

document.getElementById('save').addEventListener('click', () => {
  chrome.storage.sync.set(
    { host: hostEl.value.trim(), token: tokenEl.value.trim() },
    () => {
      savedEl.textContent = '✅ 已保存';
      setTimeout(() => (savedEl.textContent = ''), 2000);
    }
  );
});
