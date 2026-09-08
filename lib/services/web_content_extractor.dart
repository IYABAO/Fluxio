/// 跨平台共享的网页全文提取脚本。
///
/// 全量模式：提取 `<body>` 的完整可见文本，只剔除脚本/样式/内嵌框架等
/// 不可见或非文本元素，**不做任何正文容器精简、不截断**，保证收藏内容完整。
///
/// 提取前会克隆节点，因此不修改原页面 DOM。返回值是纯文本字符串。
const String kExtractContentJs = '''
(() => {
  function clean(el) {
    if (!el) return '';
    var c = el.cloneNode(true);
    var sel = 'script,style,noscript,iframe,svg,template,canvas,audio,video';
    c.querySelectorAll(sel).forEach(function(n) {
      if (n.parentNode) n.parentNode.removeChild(n);
    });
    var t = (c.innerText || c.textContent || '')
      .replace(/[ \\t]+/g, ' ')
      .replace(/\\n{3,}/g, '\\n\\n')
      .trim();
    return t;
  }
  return clean(document.body);
})()
''';

/// 获取当前页面纵向滚动位置（返回数字）。兼容性保留。
const String kGetScrollYJs = 'window.scrollY || document.documentElement.scrollTop || 0;';

/// 简单把页面滚动到指定位置（兼容性保留）。
String kScrollToJs(int y) => 'window.scrollTo(0, $y); true;';

/// 提取**自包含**整页 HTML 快照（保留样式/图片/布局）。
///
/// 相比裸 `outerHTML`，本脚本额外做了：
/// 1. 收集页面所有内联 `<style>`（含 SPA 运行时动态插入的样式）；
/// 2. 尝试 `fetch` 内联所有外链 `<link rel="stylesheet">` 的 CSS 内容，
///    让本地打开 `.html` 时不再依赖在线外链（跨域/防盗链失败时保留原 link）；
/// 3. 把收集到的全部样式注入 `<head>`。
///
/// 使用 async IIFE：WebView2 的 `ExecuteScriptAsync` 会等待 Promise 完成。
const String kExtractHtmlJs = '''
(async function() {
  try {
    var extraCss = [];
    var styleNodes = document.querySelectorAll('style');
    for (var i = 0; i < styleNodes.length; i++) {
      var t = styleNodes[i].textContent || '';
      if (t.trim()) extraCss.push(t);
    }
    var links = document.querySelectorAll('link[rel="stylesheet"]');
    for (var j = 0; j < links.length; j++) {
      var href = links[j].href;
      if (!href) continue;
      try {
        var ctrl = new AbortController();
        var to = setTimeout(function() { ctrl.abort(); }, 5000);
        var resp = await fetch(href, {signal: ctrl.signal});
        clearTimeout(to);
        if (resp && resp.ok) {
          var css = await resp.text();
          if (css && css.trim()) extraCss.push(css);
        }
      } catch (e) {}
    }
    var html = document.documentElement.outerHTML;
    var styleBlock = '<style data-fluxio-inline="1">' + extraCss.join('\\n') + '</style>';
    var headIdx = html.toLowerCase().indexOf('</head>');
    if (headIdx >= 0) {
      html = html.slice(0, headIdx) + styleBlock + html.slice(headIdx);
    } else {
      html = '<head>' + styleBlock + '</head>' + html;
    }
    return html;
  } catch (e) {
    return document.documentElement.outerHTML;
  }
})()
''';

/// 注入页面滚动监听：页面滚动/加载时通过宿主桥把纵向滚动位置实时上报。
///
/// **滚动容器自适应**：很多信息流站（尤其 SPA）的主滚动容器不是 `window`，
/// 而是内部某个 `overflow-y:auto` 的 div。脚本会：
/// 1. 若已标记过容器（`[data-fluxio-scroll]`，SPA 内 keep-alive 复用）直接用；
/// 2. 否则若 `window` 本身可滚（scrollY>0）→ 按 window 滚动上报；
/// 3. 否则遍历查找第一个"可滚动且足够大"的容器，打上标记后上报其 scrollTop。
/// 这样 Dart 端拿到的永远是**真实滚动容器**的位置，恢复时才不会错位。
///
/// Windows WebView2 用 `window.chrome.webview.postMessage`；
/// 移动端 WebView（webview_flutter JS channel）用 `window.FluxioBridge.postMessage`。
/// 两种都 try/catch 兼容。
///
/// 用 `window.__fluxioScrollInstalled` 标记防止同一 document 内重复注入。
const String kInstallScrollListenerJs = '''
(function() {
  if (window.__fluxioScrollInstalled) return;
  window.__fluxioScrollInstalled = true;
  var boundScroller = null;
  function findScroller() {
    var el = document.querySelector('[data-fluxio-scroll]');
    if (el) return el;
    if ((window.scrollY || document.documentElement.scrollTop || 0) > 0) return null;
    var all = document.querySelectorAll('body *');
    for (var i = 0; i < all.length; i++) {
      var c = all[i];
      if (c.scrollHeight - c.clientHeight > 100) {
        var s = window.getComputedStyle(c);
        if (/(auto|scroll|overlay)/.test(s.overflowY) && c.clientHeight > 200) {
          c.setAttribute('data-fluxio-scroll', '1');
          return c;
        }
      }
    }
    return null;
  }
  function send() {
    var el = findScroller();
    if (el && el !== boundScroller) {
      el.addEventListener('scroll', send, {passive: true});
      boundScroller = el;
    }
    var y = el ? el.scrollTop : (window.scrollY || document.documentElement.scrollTop || 0);
    var payload = JSON.stringify({fluxio: 'scroll', y: y, container: el ? 'el' : 'window'});
    try { window.chrome.webview.postMessage(payload); } catch (e) {}
    try { window.FluxioBridge && window.FluxioBridge.postMessage(payload); } catch (e) {}
  }
  window.addEventListener('scroll', send, {passive: true});
  window.addEventListener('load', function() { setTimeout(send, 300); });
  setTimeout(send, 1000);
  setInterval(send, 500);
  send();
  // 拦截用户点击的链接：阻止默认导航，通过 postMessage 把 URL 发给 Dart 端
  // Dart 端收到后打开全屏新页面加载详情，信息流页面保持不变（滚动位置自然保留）。
  document.addEventListener('click', function(e) {
    var a = e.target.closest('a');
    if (!a || !a.href) return;
    var href = a.getAttribute('href') || '';
    // 排除锚点、javascript、mailto、tel 等非页面导航链接
    if (href.startsWith('#') || href.startsWith('javascript:') || href.startsWith('mailto:') || href.startsWith('tel:')) return;
    if (!a.href.startsWith('http')) return;
    e.preventDefault();
    e.stopPropagation();
    var payload = JSON.stringify({fluxio: 'navigate', url: a.href});
    try { window.chrome.webview.postMessage(payload); } catch (err) {}
    try { window.FluxioBridge && window.FluxioBridge.postMessage(payload); } catch (err) {}
  }, true);
})();
''';

/// 恢复信息流首页滚动位置（**滚动容器自适应**）。
///
/// 与监听脚本同一套容器识别逻辑：优先恢复 `[data-fluxio-scroll]` 容器的
/// scrollTop；同时兜底设置 window / documentElement / body 的 scrollTop，
/// 覆盖"SPA 内容异步加载后容器重建"的场景。参数 [y] 由调用方拼接。
String kRestoreScrollJs(int y) => '''
(function() {
  var el = document.querySelector('[data-fluxio-scroll]');
  if (!el) {
    var all = document.querySelectorAll('body *');
    for (var i = 0; i < all.length; i++) {
      var c = all[i];
      if (c.scrollHeight - c.clientHeight > 100) {
        var s = window.getComputedStyle(c);
        if (/(auto|scroll|overlay)/.test(s.overflowY) && c.clientHeight > 200) {
          el = c;
          c.setAttribute('data-fluxio-scroll', '1');
          break;
        }
      }
    }
  }
  if (el) el.scrollTop = $y;
  window.scrollTo(0, $y);
  document.documentElement.scrollTop = $y;
  document.body.scrollTop = $y;
  return true;
})();
''';
