// popup：状态显示 + 一键收藏
const statusEl = document.getElementById('status');
const btn = document.getElementById('btn');
const resultEl = document.getElementById('result');

async function refreshStatus() {
  const r = await chrome.runtime.sendMessage({ type: 'inbox-status' });
  statusEl.textContent = r?.ok
    ? '● Fluxio 服务连接正常'
    : '● Fluxio 未连接（请确认应用已启动）';
}

btn.addEventListener('click', async () => {
  btn.disabled = true;
  btn.textContent = '收藏中…';
  resultEl.textContent = '';
  const r = await chrome.runtime.sendMessage({ type: 'inbox-save' });
  if (r?.ok) {
    resultEl.className = 'ok';
    resultEl.textContent = `✅ 已收藏 → ${r.record || '收件箱'}`;
  } else {
    resultEl.className = 'err';
    resultEl.textContent = `❌ ${r?.error || '未知错误'}`;
  }
  btn.disabled = false;
  btn.textContent = '收藏当前页到 Obsidian';
});

refreshStatus();
