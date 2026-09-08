// Fluxio 收藏助手：后台逻辑（投递当前页到本地收件服务）
const DEFAULT_HOST = 'http://127.0.0.1:8730';

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === 'inbox-save') {
    saveCurrentTab()
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }
  if (msg?.type === 'inbox-status') {
    getStatus().then(sendResponse);
    return true;
  }
});

async function getConfig() {
  const cfg = await chrome.storage.sync.get(['host', 'token']);
  return {
    host: cfg.host || DEFAULT_HOST,
    token: cfg.token || '',
  };
}

// 注入到页面的函数：提取渲染后的正文，转换为 Markdown，生成带 CSS 限制的 HTML 快照
// 注意：此函数会被序列化后注入页面执行，不能引用外部变量
function extractPageContent() {
  function inline(node) {
    if (node.nodeType === 3) return node.textContent;
    if (node.nodeType !== 1) return '';
    const tag = node.tagName.toLowerCase();
    const children = Array.from(node.childNodes).map(inline).join('');
    switch (tag) {
      case 'strong': case 'b': return '**' + children + '**';
      case 'em': case 'i': return '*' + children + '*';
      case 'del': case 's': return '~~' + children + '~~';
      case 'code': return '`' + children + '`';
      case 'a': {
        const href = node.getAttribute('href') || '';
        if (!href || href.startsWith('#') || href.startsWith('javascript:')) return children;
        return '[' + (children || href) + '](' + href + ')';
      }
      case 'img': {
        const src = node.getAttribute('src') || '';
        const alt = node.getAttribute('alt') || '';
        return src ? '![' + alt + '](' + src + ')' : '';
      }
      case 'br': return '\n';
      case 'span': case 'font': case 'sub': case 'sup': case 'mark': case 'small': return children;
      default: return children;
    }
  }

  function block(node) {
    if (node.nodeType === 3) {
      const t = node.textContent.trim();
      return t ? t + '\n' : '';
    }
    if (node.nodeType !== 1) return '';
    const tag = node.tagName.toLowerCase();
    if (['script','style','noscript','svg','canvas','iframe','form','button','input','select','textarea','nav','footer'].includes(tag)) return '';

    const children = Array.from(node.childNodes);
    switch (tag) {
      case 'h1': return '# ' + inline(node) + '\n\n';
      case 'h2': return '## ' + inline(node) + '\n\n';
      case 'h3': return '### ' + inline(node) + '\n\n';
      case 'h4': return '#### ' + inline(node) + '\n\n';
      case 'h5': return '##### ' + inline(node) + '\n\n';
      case 'h6': return '###### ' + inline(node) + '\n\n';
      case 'p': return inline(node) + '\n\n';
      case 'br': return '\n';
      case 'hr': return '---\n\n';
      case 'blockquote': return children.map(block).join('').split('\n').map(l => l ? '> ' + l : '>').join('\n') + '\n\n';
      case 'pre': return '```\n' + node.textContent.trim() + '\n```\n\n';
      case 'ul': case 'ol': {
        return children.map((li, i) => {
          if (li.tagName && li.tagName.toLowerCase() === 'li') {
            const prefix = tag === 'ol' ? (i+1) + '. ' : '- ';
            return prefix + inline(li) + '\n';
          }
          return '';
        }).join('') + '\n';
      }
      case 'table': {
        const rows = node.querySelectorAll('tr');
        if (!rows.length) return '';
        let md = '';
        rows.forEach((tr, idx) => {
          const cells = Array.from(tr.children).map(c => inline(c).trim().replace(/\n/g,' '));
          md += '| ' + cells.join(' | ') + ' |\n';
          if (idx === 0) md += '| ' + cells.map(() => '---').join(' | ') + ' |\n';
        });
        return md + '\n';
      }
      case 'div': case 'section': case 'article': case 'main': case 'figure': case 'figcaption': case 'aside':
      case 'li': case 'dd': case 'dt': case 'dl': case 'address':
        return children.map(block).join('');
      default:
        return inline(node) + '\n';
    }
  }

  function getMainContent() {
    const selectors = ['article', 'main', '[role="main"]', '.post-content', '.article-content', '.entry-content', '.markdown-body', '#content', '.content'];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el && el.textContent.trim().length > 200) return el;
    }
    return document.body;
  }

  const mainEl = getMainContent();
  let markdown = block(mainEl).replace(/\n{3,}/g, '\n\n').trim();

  // 生成 HTML 快照前，用 JS 修改 DOM——但必须保存原始状态，生成后恢复，避免污染原页面
  const origin = location.origin;
  const originals = [];
  const allTargets = document.querySelectorAll('svg, img, [class*="icon"], [class*="Icon"], [class*="logo"], [class*="Logo"], link[href^="/"], script[src^="/"], img[src^="/"], a[href^="/"], source[srcset]');
  allTargets.forEach(el => {
    originals.push({
      el: el,
      style: el.style.cssText,
      width: el.getAttribute('width'),
      height: el.getAttribute('height'),
      href: el.getAttribute('href'),
      src: el.getAttribute('src'),
      srcset: el.getAttribute('srcset'),
    });
  });

  // === 关键修复：把所有绝对路径替换为完整 URL（file:// 协议下绝对路径会失效）===
  // /css/main.css → https://www.plbear.com/css/main.css
  document.querySelectorAll('link[href^="/"], script[src^="/"], img[src^="/"], a[href^="/"], source[src^="/"], video[src^="/"], audio[src^="/"]').forEach(el => {
    const attr = el.hasAttribute('href') ? 'href' : 'src';
    const val = el.getAttribute(attr);
    if (val && val.startsWith('/') && !val.startsWith('//')) {
      el.setAttribute(attr, origin + val);
    }
  });
  // 替换 srcset 里的绝对路径
  document.querySelectorAll('img[srcset], source[srcset]').forEach(el => {
    const srcset = el.getAttribute('srcset');
    if (srcset && srcset.includes('/')) {
      el.setAttribute('srcset', srcset.replace(/(^|,\s*)(\/[^,\s]+)/g, '$1' + origin + '$2'));
    }
  });
  // 替换 CSS 里的 url(/...) 绝对路径（内联 style 和 style 标签）
  document.querySelectorAll('[style]').forEach(el => {
    const style = el.getAttribute('style');
    if (style && /url\(\s*["']?\//.test(style)) {
      el.setAttribute('style', style.replace(/url\(\s*["']?(\/[^)"']+)["']?\s*\)/g, 'url(' + origin + '$1)'));
    }
  });

  document.querySelectorAll('svg').forEach(svg => {
    const cls = (svg.getAttribute('class') || '') + ' ' + (svg.parentElement?.getAttribute('class') || '');
    const isIcon = /icon|logo|avatar|symbol|sprite|menu|arrow|chevron|social|share|search|close|hamburger/i.test(cls)
      || svg.closest('button, a, nav, [class*="icon"], [class*="logo"], [class*="social"], [class*="menu"], [class*="nav"]');
    const rect = svg.getBoundingClientRect();
    const isSmall = rect.width > 0 && rect.width < 64 && rect.height < 64;

    if (isIcon || isSmall) {
      svg.setAttribute('width', '20');
      svg.setAttribute('height', '20');
      svg.style.width = '20px';
      svg.style.height = '20px';
      svg.style.maxWidth = '24px';
      svg.style.maxHeight = '24px';
      svg.style.display = 'inline-block';
      svg.style.verticalAlign = 'middle';
    } else {
      svg.removeAttribute('width');
      svg.removeAttribute('height');
      svg.style.maxWidth = '100%';
      svg.style.maxHeight = '600px';
      svg.style.width = 'auto';
      svg.style.height = 'auto';
      svg.style.display = 'block';
    }
  });
  document.querySelectorAll('[class*="icon"], [class*="Icon"], [class*="logo"], [class*="Logo"]').forEach(el => {
    if (el.tagName !== 'svg' && el.tagName !== 'SVG') {
      el.style.maxWidth = '24px';
      el.style.maxHeight = '24px';
      el.style.width = 'auto';
      el.style.height = 'auto';
      el.style.display = 'inline-block';
    }
  });
  document.querySelectorAll('img').forEach(img => {
    img.style.maxWidth = '100%';
    img.style.height = 'auto';
    img.style.display = 'block';
  });
  const styleEl = document.createElement('style');
  styleEl.textContent = 'img { max-width: 100% !important; height: auto !important; } svg { max-width: 100%; height: auto; } [class*="icon"], [class*="Icon"], [class*="logo"], [class*="Logo"] { max-width: 24px !important; max-height: 24px !important; }';
  document.head.appendChild(styleEl);
  const html = '<!DOCTYPE html>\n' + document.documentElement.outerHTML;

  // === 关键：恢复原页面所有被修改元素的原始状态 ===
  styleEl.remove();
  originals.forEach(({el, style, width, height, href, src, srcset}) => {
    el.style.cssText = style;
    if (width === null) el.removeAttribute('width'); else el.setAttribute('width', width);
    if (height === null) el.removeAttribute('height'); else el.setAttribute('height', height);
    if (href === null) el.removeAttribute('href'); else el.setAttribute('href', href);
    if (src === null) el.removeAttribute('src'); else el.setAttribute('src', src);
    if (srcset === null) el.removeAttribute('srcset'); else el.setAttribute('srcset', srcset);
  });

  return {
    title: document.title || '',
    url: location.href,
    markdown: markdown,
    html: html
  };
}

async function saveCurrentTab() {
  const cfg = await getConfig();
  if (!cfg.token) {
    return {
      ok: false,
      error: '未配置 Token：右键图标 → 选项，粘贴 Fluxio 设置页的 Token',
    };
  }
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url || !/^https?:/.test(tab.url)) {
    return { ok: false, error: '当前页面不是 http(s) 网页' };
  }

  // 注入脚本提取渲染后的正文（Markdown + HTML 快照）
  let extracted = null;
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: extractPageContent,
    });
    extracted = results?.[0]?.result;
  } catch (e) {
    console.warn('内容提取失败，回退到仅 URL 模式:', e);
  }

  const body = {
    url: tab.url,
    title: tab.title || extracted?.title || '',
    source: '浏览器扩展',
  };
  // 如果提取到了 Markdown 正文和 HTML 快照，直接传给 Fluxio（不需要 Fluxio 再 fetch）
  if (extracted?.markdown && extracted.markdown.length > 50) {
    body.content = extracted.markdown;
  }
  if (extracted?.html && extracted.html.length > 500) {
    body.html = extracted.html;
  }

  const res = await fetch(`${cfg.host}/api/inbox`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Inbox-Token': cfg.token,
    },
    body: JSON.stringify(body),
  });
  let data = null;
  try {
    data = await res.json();
  } catch (_) {
    data = { ok: false, error: `HTTP ${res.status}` };
  }
  return data;
}

async function getStatus() {
  const cfg = await getConfig();
  try {
    const res = await fetch(`${cfg.host}/api/health`);
    const data = await res.json();
    return { ok: data?.ok === true, error: null };
  } catch (e) {
    return { ok: false, error: '无法连接 Fluxio（请确认应用已启动）' };
  }
}
