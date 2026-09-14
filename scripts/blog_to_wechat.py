#!/usr/bin/env python3
"""
博客文章转公众号格式工具。

把 www.plbear.com 的博客文章转换成公众号编辑器兼容的富文本 HTML，
直接复制粘贴到公众号后台即可发布。

功能：
- 从博客 URL 抓取文章正文
- 自动处理图片（转成 jsDelivr CDN 链接，公众号支持外链图片）
- 自动处理代码块（公众号不支持 <pre><code>，转成好看的样式）
- 自动处理标题、引用、列表、表格等排版
- 生成带封面图、摘要的完整草稿
- 输出可直接复制的 HTML 文件

使用方法：
  python blog_to_wechat.py https://www.plbear.com/posts/xxx/
  python blog_to_wechat.py https://www.plbear.com/posts/xxx/ -o output.html
"""

import argparse
import base64
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup, Tag

# ── 配置 ──────────────────────────────────────────────────────

BLOG_BASE = "https://www.plbear.com"
IMAGE_CDN_BASE = "https://cdn.jsdelivr.net/gh/IYABAO/IYABAO.github.io@master/static/images/"

# 公众号兼容的 CSS 样式
WECHAT_STYLES = """
<style>
/* 全局 */
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; font-size: 16px; line-height: 1.75; color: #333; max-width: 677px; margin: 0 auto; padding: 20px; }

/* 标题 */
h1 { font-size: 24px; font-weight: bold; margin: 30px 0 16px; color: #1a1a1a; border-bottom: 2px solid #07c160; padding-bottom: 8px; }
h2 { font-size: 20px; font-weight: bold; margin: 28px 0 14px; color: #1a1a1a; border-left: 4px solid #07c160; padding-left: 12px; }
h3 { font-size: 18px; font-weight: bold; margin: 24px 0 12px; color: #333; }
h4 { font-size: 16px; font-weight: bold; margin: 20px 0 10px; color: #555; }

/* 段落 */
p { margin: 16px 0; }

/* 图片 */
img { max-width: 100%; height: auto; display: block; margin: 20px auto; border-radius: 8px; }

/* 引用 */
blockquote { border-left: 4px solid #07c160; background: #f7f7f7; margin: 20px 0; padding: 12px 16px; color: #666; border-radius: 0 8px 8px 0; }
blockquote p { margin: 8px 0; }

/* 代码块 */
pre { background: #1e1e1e; color: #d4d4d4; padding: 16px; border-radius: 8px; overflow-x: auto; margin: 20px 0; font-family: "Consolas", "Monaco", "Courier New", monospace; font-size: 14px; line-height: 1.6; }
pre code { background: none; padding: 0; color: #d4d4d4; }
code { background: #f0f0f0; color: #e83e8c; padding: 2px 6px; border-radius: 4px; font-family: "Consolas", "Monaco", "Courier New", monospace; font-size: 14px; }

/* 列表 */
ul, ol { margin: 16px 0; padding-left: 24px; }
li { margin: 8px 0; }

/* 表格 */
table { border-collapse: collapse; width: 100%; margin: 20px 0; font-size: 14px; }
th, td { border: 1px solid #ddd; padding: 10px 12px; }
th { background: #f7f7f7; font-weight: bold; color: #333; }
tr:nth-child(even) { background: #fafafa; }

/* 链接 */
a { color: #07c160; text-decoration: none; }
a:hover { text-decoration: underline; }

/* 分割线 */
hr { border: none; border-top: 1px solid #eee; margin: 30px 0; }

/* 强调 */
strong { color: #1a1a1a; font-weight: bold; }
em { color: #666; }

/* 文章头部信息 */
.article-meta { color: #999; font-size: 14px; margin-bottom: 20px; }
.article-meta span { margin-right: 16px; }
</style>
"""


# ── 文章抓取 ──────────────────────────────────────────────────

def fetch_article(url: str) -> Optional[dict]:
    """用 Playwright 抓取博客文章，同时把页面上的 SVG 截图成 PNG。
    这样 SVG 会继承页面的完整 CSS 样式，截图出来的图片显示正常。"""
    print(f"📡 正在抓取文章: {url}")

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("⚠️  Playwright 未安装，回退到 requests 抓取（SVG 可能显示异常）")
        return fetch_article_requests(url)

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="msedge")
            page = browser.new_page(viewport={'width': 1000, 'height': 800})
            page.goto(url, wait_until='networkidle', timeout=30000)
            page.wait_for_timeout(1000)  # 等待 SVG 渲染完成

            # 提取标题
            title = page.evaluate("""() => {
                const h1 = document.querySelector('h1.post-title') || document.querySelector('h1');
                return h1 ? h1.textContent.trim() : '';
            }""")

            # 提取发布时间
            date = page.evaluate("""() => {
                const time = document.querySelector('time') || document.querySelector('.post-meta');
                return time ? time.textContent.trim() : '';
            }""")

            # 找到所有 SVG 元素，逐个截图
            svg_count = page.evaluate("() => document.querySelectorAll('.post-content svg, article svg').length")
            print(f"🖼️  发现 {svg_count} 个 SVG，正在页面上截图...")

            svg_images = []
            for i in range(svg_count):
                try:
                    svg_elements = page.query_selector_all('.post-content svg, article svg')
                    if i < len(svg_elements):
                        # 滚动到 SVG 元素位置，确保可见
                        svg_elements[i].scroll_into_view_if_needed()
                        page.wait_for_timeout(200)
                        # 截图
                        png_bytes = svg_elements[i].screenshot()
                        base64_data = base64.b64encode(png_bytes).decode('utf-8')
                        svg_images.append(f"data:image/png;base64,{base64_data}")
                        print(f"  ✅ SVG #{i+1} 已截图 ({len(png_bytes)//1024} KB)")
                    else:
                        svg_images.append(None)
                except Exception as e:
                    print(f"  ⚠️  SVG #{i+1} 截图失败: {e}")
                    svg_images.append(None)

            # 用 JavaScript 把页面上的 SVG 替换成 img 标签
            content = page.evaluate("""(svgImages) => {
                const content = document.querySelector('.post-content') || document.querySelector('article');
                if (!content) return '';

                // 移除不需要的元素
                const selectors = ['.post-tags', '.post-categories', '.share-buttons',
                                   '.related-posts', '.pagination', '.comments',
                                   'script', 'style', 'nav', 'footer', 'header'];
                selectors.forEach(sel => {
                    content.querySelectorAll(sel).forEach(el => el.remove());
                });

                // 把 SVG 替换成 img
                const svgs = content.querySelectorAll('svg');
                svgs.forEach((svg, i) => {
                    if (svgImages[i]) {
                        const img = document.createElement('img');
                        img.src = svgImages[i];
                        img.alt = '流程图 ' + (i+1);
                        img.style.maxWidth = '100%';
                        img.style.height = 'auto';
                        img.style.display = 'block';
                        img.style.margin = '20px auto';
                        img.style.borderRadius = '8px';
                        svg.replaceWith(img);
                    }
                });

                // 彻底清理所有可能导致公众号警告的内联样式
                content.querySelectorAll('*').forEach(el => {
                    if (!el.style) return;
                    // 1. 移除所有 text-align（公众号会自动转成 start，导致警告）
                    el.style.removeProperty('text-align');
                    // 2. 移除所有宽度设置（可能导致溢出或居中不一致）
                    el.style.removeProperty('width');
                    el.style.removeProperty('max-width');
                    el.style.removeProperty('min-width');
                    // 3. 移除过大的左侧缩进（可能导致溢出）
                    const marginLeft = parseFloat(el.style.marginLeft);
                    if (marginLeft > 50) el.style.removeProperty('margin-left');
                    const paddingLeft = parseFloat(el.style.paddingLeft);
                    if (paddingLeft > 50) el.style.removeProperty('padding-left');
                    // 4. 移除 position（可能破坏排版顺序）
                    el.style.removeProperty('position');
                    el.style.removeProperty('left');
                    el.style.removeProperty('right');
                    el.style.removeProperty('top');
                    el.style.removeProperty('bottom');
                    // 5. 移除 transform（可能导致显示异常）
                    el.style.removeProperty('transform');
                });

                return content.innerHTML;
            }""", svg_images)

            browser.close()

            if not content:
                print("❌ 找不到文章正文")
                return None

            return {
                "title": title,
                "date": date,
                "content": content,
                "url": url,
            }

    except Exception as e:
        print(f"❌ Playwright 抓取失败: {e}，回退到 requests")
        return fetch_article_requests(url)


def fetch_article_requests(url: str) -> Optional[dict]:
    """用 requests 抓取文章（备用方案，SVG 可能显示异常）。"""
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        resp = requests.get(url, headers=headers, timeout=15)
        resp.raise_for_status()
        resp.encoding = "utf-8"

        soup = BeautifulSoup(resp.text, "html.parser")

        # 提取标题
        title = ""
        title_tag = soup.find("h1", class_="post-title") or soup.find("h1")
        if title_tag:
            title = title_tag.get_text(strip=True)

        # 提取发布时间
        date = ""
        date_tag = soup.find("time") or soup.find(class_="post-meta")
        if date_tag:
            date = date_tag.get_text(strip=True)

        # 提取正文（PaperMod 主题的正文在 .post-content 里）
        content = soup.find("div", class_="post-content")
        if not content:
            content = soup.find("article")
        if not content:
            print("❌ 找不到文章正文")
            return None

        # 移除不需要的元素
        for selector in [".post-tags", ".post-categories", ".share-buttons",
                         ".related-posts", ".pagination", ".comments",
                         "script", "style", "nav", "footer", "header"]:
            for el in content.select(selector):
                el.decompose()

        return {
            "title": title,
            "date": date,
            "content": str(content),
            "url": url,
        }
    except Exception as e:
        print(f"❌ 抓取文章失败: {e}")
        return None


# ── 内容转换 ──────────────────────────────────────────────────

def convert_images(content_html: str) -> str:
    """处理图片：把相对路径转成 CDN 链接，确保公众号能显示。"""
    soup = BeautifulSoup(content_html, "html.parser")

    for img in soup.find_all("img"):
        src = img.get("src", "")
        if not src:
            continue

        # 处理相对路径
        if src.startswith("/"):
            src = urljoin(BLOG_BASE, src)
        elif src.startswith("http"):
            pass  # 已经是绝对路径
        else:
            src = urljoin(BLOG_BASE, src)

        # 如果是博客本地图片，转成 jsDelivr CDN 链接
        # 例如：https://www.plbear.com/images/xxx.jpg -> CDN
        if "plbear.com" in src and "/images/" in src:
            filename = src.split("/images/")[-1]
            src = IMAGE_CDN_BASE + filename

        img["src"] = src

        # 确保图片有 alt
        if not img.get("alt"):
            img["alt"] = "图片"

    return str(soup)


def convert_code_blocks(content_html: str) -> str:
    """处理代码块：确保公众号编辑器兼容。"""
    soup = BeautifulSoup(content_html, "html.parser")

    # 处理 <pre><code> 结构
    for pre in soup.find_all("pre"):
        # 提取代码内容
        code = pre.find("code")
        if code:
            code_text = code.get_text()
            # 保留语言类名（用于语法高亮提示）
            lang = ""
            for cls in code.get("class", []):
                if cls.startswith("language-"):
                    lang = cls.replace("language-", "")
                    break

            # 重建 pre 标签，确保样式正确
            new_pre = soup.new_tag("pre")
            if lang:
                new_pre["data-lang"] = lang
            new_code = soup.new_tag("code")
            new_code.string = code_text
            new_pre.append(new_code)
            pre.replace_with(new_pre)

    # 处理行内代码
    for code in soup.find_all("code"):
        if code.parent and code.parent.name == "pre":
            continue  # 跳过代码块里的 code
        # 行内代码保持原样，CSS 会处理

    return str(soup)


def convert_links(content_html: str) -> str:
    """处理链接：确保相对路径转绝对路径。"""
    soup = BeautifulSoup(content_html, "html.parser")

    for a in soup.find_all("a"):
        href = a.get("href", "")
        if href.startswith("/"):
            a["href"] = urljoin(BLOG_BASE, href)
        elif href.startswith("#"):
            # 锚点链接，公众号里可能不生效，保留但加个提示
            pass

    return str(soup)


def clean_html(content_html: str) -> str:
    """清理 HTML，移除公众号不支持的标签和属性。"""
    soup = BeautifulSoup(content_html, "html.parser")

    # SVG 标签及其内部元素保留所有属性（公众号对 SVG 支持有限，但保留属性至少能显示）
    svg_tags = {"svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline",
                "polygon", "text", "tspan", "use", "defs", "linearGradient", "stop",
                "filter", "feGaussianBlur", "feOffset", "feBlend", "clipPath", "mask"}

    # 移除所有 class 和 id 属性（公众号不支持）
    for tag in soup.find_all(True):
        if tag.name in svg_tags:
            # SVG 相关标签保留所有属性
            continue
        # 保留 img 的 src 和 alt，a 的 href
        if tag.name == "img":
            attrs_to_keep = ["src", "alt", "width", "height"]
            for attr in list(tag.attrs.keys()):
                if attr not in attrs_to_keep:
                    del tag[attr]
        elif tag.name == "a":
            attrs_to_keep = ["href", "title"]
            for attr in list(tag.attrs.keys()):
                if attr not in attrs_to_keep:
                    del tag[attr]
        elif tag.name in ["pre", "code"]:
            # 保留代码块的 data-lang
            pass
        else:
            # 其他标签移除所有属性
            tag.attrs = {}

    return str(soup)


def fix_svg_styles(content_html: str) -> str:
    """给 SVG 加上样式，确保在公众号里能正常显示。"""
    soup = BeautifulSoup(content_html, "html.parser")

    for svg in soup.find_all("svg"):
        # 确保 SVG 有 width 和 height
        has_width = svg.get("width") is not None
        has_height = svg.get("height") is not None

        if not has_width:
            svg["width"] = "677"
        if not has_height:
            svg["height"] = "400"

        # 确保 viewBox 正确（这是关键！没有 viewBox 会导致缩放异常）
        if not svg.get("viewBox"):
            try:
                w = int(float(str(svg["width"]).replace("px", "").replace("%", "")))
                h = int(float(str(svg["height"]).replace("px", "").replace("%", "")))
                svg["viewBox"] = f"0 0 {w} {h}"
            except (ValueError, TypeError):
                svg["viewBox"] = "0 0 677 400"

        # 给 SVG 加上 style
        svg["style"] = "max-width: 100%; width: 100%; height: auto; display: block; margin: 20px auto; background: #fff; padding: 15px; border-radius: 8px; overflow: visible;"

        # 确保 SVG 有 xmlns
        if not svg.get("xmlns"):
            svg["xmlns"] = "http://www.w3.org/2000/svg"

        # 给所有 text 元素加上统一的字体大小和样式
        for text in svg.find_all(["text", "tspan"]):
            # 只有当没有设置 font-size 时才设置默认值
            if not text.get("font-size") and not text.get("style"):
                text["font-size"] = "14"
            if not text.get("font-family"):
                text["font-family"] = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"

        # 给所有 g 元素加上样式继承
        for g in svg.find_all("g"):
            if not g.get("font-size") and not g.get("style"):
                g["font-size"] = "14"
            if not g.get("font-family"):
                g["font-family"] = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"

    return str(soup)


def svg_to_png_base64(svg_content: str, index: int) -> Optional[str]:
    """把 SVG 转成 PNG，返回 base64 编码。使用 Playwright 截图。"""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("⚠️  Playwright 未安装，SVG 将保留原样（可能显示异常）")
        return None

    try:
        # 把 SVG 保存成临时文件
        with tempfile.NamedTemporaryFile(mode='w', suffix='.svg', delete=False, encoding='utf-8') as f:
            f.write(svg_content)
            svg_path = f.name

        png_path = svg_path.replace('.svg', '.png')

        with sync_playwright() as p:
            # 使用 Windows 自带的 Edge 浏览器，不需要额外下载
            browser = p.chromium.launch(channel="msedge")
            page = browser.new_page(viewport={'width': 1200, 'height': 800})
            page.goto(f'file:///{svg_path.replace(os.sep, "/")}')
            page.wait_for_timeout(500)

            # 找到 SVG 元素并截图
            svg_element = page.query_selector('svg')
            if svg_element:
                svg_element.screenshot(path=png_path)
            else:
                page.screenshot(path=png_path, full_page=True)

            browser.close()

        # 读取 PNG 并转成 base64
        with open(png_path, 'rb') as f:
            png_data = f.read()
        base64_data = base64.b64encode(png_data).decode('utf-8')

        # 清理临时文件
        try:
            os.unlink(svg_path)
            os.unlink(png_path)
        except:
            pass

        print(f"  ✅ SVG #{index} 已转成 PNG ({len(png_data)//1024} KB)")
        return f"data:image/png;base64,{base64_data}"

    except Exception as e:
        print(f"  ⚠️  SVG #{index} 转 PNG 失败: {e}，保留原样")
        return None


def convert_svg_to_images(content_html: str) -> str:
    """把所有 SVG 转成 PNG 图片（base64 内嵌）。"""
    soup = BeautifulSoup(content_html, "html.parser")
    svgs = soup.find_all("svg")

    if not svgs:
        return content_html

    print(f"🖼️  发现 {len(svgs)} 个 SVG，正在转成 PNG...")

    for i, svg in enumerate(svgs, 1):
        svg_str = str(svg)
        png_base64 = svg_to_png_base64(svg_str, i)

        if png_base64:
            # 用 img 标签替换 SVG
            img_tag = soup.new_tag("img")
            img_tag["src"] = png_base64
            img_tag["alt"] = f"流程图 {i}"
            svg.replace_with(img_tag)
        # 如果转换失败，保留 SVG（会调用 fix_svg_styles 修复样式）

    return str(soup)


def convert_article(article: dict) -> str:
    """把文章转换成公众号兼容的完整 HTML。"""
    print("🔄 正在转换文章格式...")

    content = article["content"]

    # 依次处理
    content = convert_images(content)
    content = convert_code_blocks(content)
    content = convert_links(content)
    content = clean_html(content)
    # SVG 已经在 fetch_article 阶段被截图替换成 img 了
    # 这里只做兜底：如果还有残留的 SVG，修复样式
    content = fix_svg_styles(content)

    # 组装完整 HTML
    full_html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{article['title']}</title>
    {WECHAT_STYLES}
</head>
<body>
    <h1>{article['title']}</h1>
    <div class="article-meta">
        <span>📅 {article['date']}</span>
        <span>📝 林壮 Allen</span>
        <span>🔗 <a href="{article['url']}">阅读原文</a></span>
    </div>
    <hr>
    {content}
    <hr>
    <div style="text-align: center; color: #999; font-size: 14px; margin-top: 30px;">
        <p>—— END ——</p>
        <p>关注公众号「福清而不淡」，获取更多技术干货</p>
    </div>
</body>
</html>"""

    return full_html


# ── 主流程 ─────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="博客文章转公众号格式工具")
    parser.add_argument("url", help="博客文章 URL")
    parser.add_argument("-o", "--output", help="输出 HTML 文件路径（默认：wechat_article.html）")
    parser.add_argument("--open", action="store_true", help="转换完成后自动打开浏览器预览")
    args = parser.parse_args()

    # 1. 抓取文章
    article = fetch_article(args.url)
    if not article:
        print("❌ 文章抓取失败")
        sys.exit(1)

    print(f"✅ 文章标题: {article['title']}")
    print(f"✅ 发布时间: {article['date']}")

    # 2. 转换格式
    html = convert_article(article)

    # 3. 保存文件
    output_path = Path(args.output) if args.output else Path("wechat_article.html")
    output_path.write_text(html, encoding="utf-8")
    print(f"\n✅ 转换完成！文件已保存到: {output_path.absolute()}")
    print(f"\n📋 使用方法:")
    print(f"   1. 用浏览器打开 {output_path.name}")
    print(f"   2. Ctrl+A 全选，Ctrl+C 复制")
    print(f"   3. 打开公众号后台 → 图文消息 → 新建")
    print(f"   4. Ctrl+V 粘贴到编辑器里")
    print(f"   5. 调整封面图和摘要，点发布")

    # 4. 自动打开预览
    if args.open:
        import webbrowser
        webbrowser.open(output_path.absolute().as_uri())


if __name__ == "__main__":
    main()
