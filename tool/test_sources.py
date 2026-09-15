#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量测试 Fluxio 信息源可访问性
- 国内站点：直连测试
- 国外站点：走代理 127.0.0.1:10809
"""

import urllib.request
import urllib.error
import time
import json
import socket

# 代理地址
PROXY = "http://127.0.0.1:10809"

# 信息源列表：(名称, URL, 分组, 是否国外)
SOURCES = [
    # 国内热榜 / 多平台聚合
    ("TopHub 今日热榜", "https://tophub.today", "国内热榜", False),
    ("Buzzing 首页", "https://buzzing.cc", "国内热榜", False),
    ("NewsNow", "https://newsnow.busiyi.world", "国内热榜", False),
    ("rebang.today 今日热榜", "https://rebang.today", "国内热榜", False),
    ("糖果梦热榜", "https://tgmeng.com", "国内热榜", False),
    ("NewsHub", "https://newshub.shenzjd.com", "国内热榜", False),
    ("鱼塘热榜", "https://mmo.fish", "国内热榜", False),
    ("划水摸鱼", "https://huashuimoyu.com", "国内热榜", False),
    ("即时热榜", "http://m.jsrank.cn", "国内热榜", False),
    ("热摸爽", "https://remoshuang.com", "国内热榜", False),

    # Buzzing 子站
    ("HN 热门 (Buzzing)", "https://hn.buzzing.cc", "Buzzing 子站", False),
    ("国外新闻头条 (Buzzing)", "https://news.buzzing.cc", "Buzzing 子站", False),

    # 国外热点 + 中文翻译 / 双语
    ("ThreadEast 中国趋势英译", "https://threadeast.xyz", "国外双语", True),
    ("Horizon AI 新闻雷达", "https://thysrael.github.io/Horizon/", "国外双语", True),
    ("Ground News", "https://ground.news", "国外双语", True),
    ("Feedly", "https://feedly.com", "国外双语", True),
    ("Inoreader", "https://www.inoreader.com", "国外双语", True),
]

def test_url(url, use_proxy=False, timeout=10):
    """测试 URL 可访问性，返回 (是否成功, 状态码, 响应时间, 错误信息)"""
    try:
        # 设置超时
        socket.setdefaulttimeout(timeout)

        # 构建请求
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        req = urllib.request.Request(url, headers=headers)

        # 设置代理
        if use_proxy:
            proxy_handler = urllib.request.ProxyHandler({
                "http": PROXY,
                "https": PROXY,
            })
            opener = urllib.request.build_opener(proxy_handler)
        else:
            opener = urllib.request.build_opener()

        # 发送请求
        start = time.time()
        resp = opener.open(req, timeout=timeout)
        elapsed = time.time() - start
        status_code = resp.getcode()
        resp.close()

        return (status_code < 400, status_code, elapsed, None)

    except urllib.error.HTTPError as e:
        return (False, e.code, 0, f"HTTP 错误: {e.code} {e.reason}")
    except urllib.error.URLError as e:
        return (False, 0, 0, f"URL 错误: {e.reason}")
    except socket.timeout:
        return (False, 0, 0, "连接超时")
    except Exception as e:
        return (False, 0, 0, f"错误: {e}")

def main():
    print("=" * 80)
    print("Fluxio 信息源可访问性批量测试")
    print("=" * 80)
    print(f"代理地址: {PROXY}")
    print(f"测试站点数: {len(SOURCES)}")
    print()

    results = []
    success_count = 0
    fail_count = 0

    for name, url, group, is_foreign in SOURCES:
        proxy_str = "代理" if is_foreign else "直连"
        print(f"[{proxy_str}] 测试: {name}")
        print(f"  URL: {url}")

        success, status_code, elapsed, error = test_url(url, use_proxy=is_foreign)

        if success:
            print(f"  ✅ 成功 (状态码: {status_code}, 耗时: {elapsed:.2f}s)")
            success_count += 1
        else:
            print(f"  ❌ 失败 ({error})")
            fail_count += 1

        results.append({
            "name": name,
            "url": url,
            "group": group,
            "is_foreign": is_foreign,
            "success": success,
            "status_code": status_code,
            "elapsed": elapsed,
            "error": error,
        })
        print()

    print("=" * 80)
    print(f"测试完成: 成功 {success_count} / 失败 {fail_count} / 总计 {len(SOURCES)}")
    print("=" * 80)
    print()

    # 输出成功的站点列表（Fluxio 格式）
    print("📋 可正常访问的信息源（Fluxio JSON 格式）:")
    print("-" * 80)
    fluxio_sources = []
    for i, r in enumerate(results):
        if r["success"]:
            fluxio_sources.append({
                "id": f"preset-{i+1:03d}",
                "title": r["name"],
                "url": r["url"],
                "group": r["group"],
                "enabled": True,
                "type": "web"
            })

    print(json.dumps(fluxio_sources, ensure_ascii=False, indent=2))
    print()

    # 输出失败的站点列表
    failed = [r for r in results if not r["success"]]
    if failed:
        print("❌ 无法访问的信息源:")
        print("-" * 80)
        for r in failed:
            print(f"  - {r['name']}: {r['url']}")
            print(f"    原因: {r['error']}")
        print()

if __name__ == "__main__":
    main()
