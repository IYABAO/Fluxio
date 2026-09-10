#!/usr/bin/env python3
"""
微信公众号同步脚本：把博客文章同步到公众号「福清而不淡」。

使用方法：
1. 配置环境变量：
   export WECHAT_APP_ID="你的AppID"
   export WECHAT_APP_SECRET="你的AppSecret"

2. 运行同步：
   python wechat_sync.py --blog https://www.plbear.com --limit 5

3. 测试连接：
   python wechat_sync.py --test

功能：
- 获取博客最新文章（RSS / sitemap）
- 上传图文素材到公众号
- 发表文章（订阅号使用「发表」接口）
- 记录已同步文章，避免重复同步
"""

import argparse
import json
import os
import re
import sys
import time
import hashlib
from pathlib import Path
from typing import Optional

import requests
import xml.etree.ElementTree as ET

# ── 配置 ──────────────────────────────────────────────────────

APP_ID = os.environ.get("WECHAT_APP_ID", "")
APP_SECRET = os.environ.get("WECHAT_APP_SECRET", "")
BASE_URL = "https://api.weixin.qq.com"

# 已同步文章记录文件
SYNCED_FILE = Path(__file__).parent / "wechat_synced.json"


# ── Access Token 管理 ─────────────────────────────────────────

_token_cache = {"token": "", "expires_at": 0}


def get_access_token() -> Optional[str]:
    """获取有效的 Access Token（缓存优先，过期自动刷新）。"""
    now = time.time()
    if _token_cache["token"] and _token_cache["expires_at"] - now > 300:
        return _token_cache["token"]

    if not APP_ID or not APP_SECRET:
        print("❌ 请先设置 WECHAT_APP_ID 和 WECHAT_APP_SECRET 环境变量")
        return None

    try:
        url = f"{BASE_URL}/cgi-bin/token?grant_type=client_credential&appid={APP_ID}&secret={APP_SECRET}"
        resp = requests.get(url, timeout=10)
        data = resp.json()
        token = data.get("access_token")
        expires_in = data.get("expires_in", 7200)
        if token:
            _token_cache["token"] = token
            _token_cache["expires_at"] = now + expires_in
            print(f"✅ Access Token 获取成功（有效期 {expires_in}s）")
            return token
        else:
            print(f"❌ 获取 Access Token 失败: {data}")
            return None
    except Exception as e:
        print(f"❌ 获取 Access Token 异常: {e}")
        return None


# ── 博客文章获取 ───────────────────────────────────────────────

def fetch_blog_articles(blog_url: str, limit: int = 5) -> list[dict]:
    """从博客 RSS 获取最新文章。"""
    print(f"📡 正在获取博客文章: {blog_url}/index.xml")
    try:
        resp = requests.get(f"{blog_url}/index.xml", timeout=15)
        resp.raise_for_status()
        root = ET.fromstring(resp.content)
        channel = root.find("channel")
        if channel is None:
            print("❌ RSS 格式错误：找不到 channel")
            return []

        articles = []
        for item in channel.findall("item")[:limit]:
            title = item.findtext("title", "").strip()
            link = item.findtext("link", "").strip()
            pub_date = item.findtext("pubDate", "").strip()
            description = item.findtext("description", "").strip()
            # 去除 HTML 标签，取纯文本摘要
            summary = re.sub(r"<[^>]+>", "", description)[:200]
            articles.append({
                "title": title,
                "link": link,
                "pub_date": pub_date,
                "summary": summary,
            })
        print(f"✅ 获取到 {len(articles)} 篇文章")
        return articles
    except Exception as e:
        print(f"❌ 获取博客文章失败: {e}")
        return []


def fetch_article_content(url: str) -> Optional[str]:
    """获取文章正文 HTML（用于上传到公众号）。"""
    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        html = resp.text
        # 简单提取正文（实际项目中应使用 readability 等库）
        # 这里返回完整 HTML，公众号会自动处理
        return html
    except Exception as e:
        print(f"❌ 获取文章正文失败: {e}")
        return None


# ── 公众号 API ─────────────────────────────────────────────────

def upload_news(token: str, articles: list[dict]) -> Optional[str]:
    """上传图文素材，返回 media_id。"""
    try:
        url = f"{BASE_URL}/cgi-bin/material/add_news?access_token={token}"
        resp = requests.post(url, json={"articles": articles}, timeout=30)
        data = resp.json()
        media_id = data.get("media_id")
        if media_id:
            print(f"✅ 图文素材上传成功: media_id={media_id}")
            return media_id
        else:
            print(f"❌ 图文素材上传失败: {data}")
            return None
    except Exception as e:
        print(f"❌ 图文素材上传异常: {e}")
        return None


def publish_article(token: str, media_id: str) -> bool:
    """发表文章（订阅号使用「发表」接口）。"""
    try:
        url = f"{BASE_URL}/cgi-bin/freepublish/submit?access_token={token}"
        resp = requests.post(url, json={"media_id": media_id}, timeout=30)
        data = resp.json()
        if data.get("errcode") == 0:
            print(f"✅ 文章发表成功")
            return True
        else:
            print(f"❌ 文章发表失败: {data}")
            return False
    except Exception as e:
        print(f"❌ 文章发表异常: {e}")
        return False


# ── 同步记录 ───────────────────────────────────────────────────

def load_synced() -> set[str]:
    """加载已同步文章链接集合。"""
    if SYNCED_FILE.exists():
        try:
            data = json.loads(SYNCED_FILE.read_text(encoding="utf-8"))
            return set(data.get("synced_urls", []))
        except Exception:
            pass
    return set()


def save_synced(synced: set[str]):
    """保存已同步文章链接集合。"""
    SYNCED_FILE.write_text(
        json.dumps({"synced_urls": list(synced)}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


# ── 主流程 ─────────────────────────────────────────────────────

def test_connection():
    """测试公众号连接。"""
    print("🔍 测试公众号连接...")
    if not APP_ID or not APP_SECRET:
        print("❌ 请先设置 WECHAT_APP_ID 和 WECHAT_APP_SECRET 环境变量")
        print("   export WECHAT_APP_ID='你的AppID'")
        print("   export WECHAT_APP_SECRET='你的AppSecret'")
        return False

    token = get_access_token()
    if token:
        print("✅ 公众号连接测试成功！")
        return True
    return False


def sync_blog(blog_url: str, limit: int = 5, publish: bool = False):
    """同步博客文章到公众号。"""
    print(f"🚀 开始同步博客文章到公众号...")
    print(f"   博客地址: {blog_url}")
    print(f"   同步数量: {limit}")
    print(f"   自动发表: {'是' if publish else '否（仅上传素材）'}")
    print()

    # 1. 获取 Access Token
    token = get_access_token()
    if not token:
        print("❌ 无法获取 Access Token，同步终止")
        return

    # 2. 获取博客文章
    articles = fetch_blog_articles(blog_url, limit)
    if not articles:
        print("❌ 没有获取到文章，同步终止")
        return

    # 3. 过滤已同步文章
    synced = load_synced()
    new_articles = [a for a in articles if a["link"] not in synced]
    print(f"📊 待同步: {len(new_articles)} 篇（已跳过 {len(articles) - len(new_articles)} 篇已同步）")

    if not new_articles:
        print("✅ 所有文章都已同步，无需操作")
        return

    # 4. 逐篇同步
    success_count = 0
    for i, article in enumerate(new_articles, 1):
        print(f"\n📝 [{i}/{len(new_articles)}] 同步: {article['title']}")
        print(f"   链接: {article['link']}")

        # 获取正文
        content = fetch_article_content(article["link"])
        if not content:
            print("   ⚠️  获取正文失败，跳过")
            continue

        # 构造图文素材
        news_article = {
            "title": article["title"],
            "author": "林壮 Allen",
            "digest": article["summary"],
            "content": content,
            "content_source_url": article["link"],
            "thumb_media_id": "",  # 需要先上传封面图片
            "need_open_comment": 1,
            "only_fans_can_comment": 0,
        }

        # 上传图文素材
        media_id = upload_news(token, [news_article])
        if not media_id:
            print("   ⚠️  上传素材失败，跳过")
            continue

        # 发表文章
        if publish:
            if publish_article(token, media_id):
                success_count += 1
                synced.add(article["link"])
        else:
            success_count += 1
            synced.add(article["link"])
            print(f"   ✅ 已上传为素材（media_id={media_id}），未自动发表")

        # 保存同步记录
        save_synced(synced)

        # 避免请求过快
        time.sleep(1)

    print(f"\n🎉 同步完成！成功: {success_count}/{len(new_articles)}")


def main():
    parser = argparse.ArgumentParser(description="微信公众号同步工具")
    parser.add_argument("--blog", default="https://www.plbear.com", help="博客地址")
    parser.add_argument("--limit", type=int, default=5, help="同步文章数量")
    parser.add_argument("--publish", action="store_true", help="自动发表文章（默认仅上传素材）")
    parser.add_argument("--test", action="store_true", help="测试公众号连接")
    args = parser.parse_args()

    if args.test:
        test_connection()
    else:
        sync_blog(args.blog, args.limit, args.publish)


if __name__ == "__main__":
    main()
