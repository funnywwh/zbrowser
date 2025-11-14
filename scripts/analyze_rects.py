#!/usr/bin/env python3
"""
分析 element-rects.json，提取关键元素的矩形区域信息
"""

import json
import sys

def find_elements(data, tag_name=None, class_name=None, text_content_substring=None):
    """查找匹配的元素"""
    found = []
    for item in data:
        elem = item['element']
        rect = item['rect']
        
        match = True
        if tag_name and elem['tagName'].lower() != tag_name.lower():
            match = False
        if class_name and class_name not in elem['className'].split():
            match = False
        if text_content_substring and text_content_substring not in elem['textContent']:
            match = False
        
        if match:
            found.append({
                'element': elem,
                'rect': rect
            })
    return found

def print_comparison():
    """打印关键元素的对比信息"""
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_rects.py <element-rects.json>")
        sys.exit(1)
    
    json_file = sys.argv[1]
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    print("=" * 80)
    print("Chrome 元素矩形区域分析")
    print("=" * 80)
    
    # 1. HTML
    html_elements = find_elements(data, 'HTML')
    if html_elements:
        html = html_elements[0]
        rect = html['rect']
        print(f"\n【HTML】")
        print(f"  x: {rect['x']:.2f}px, y: {rect['y']:.2f}px")
        print(f"  width: {rect['width']:.2f}px, height: {rect['height']:.2f}px")
    
    # 2. BODY
    body_elements = find_elements(data, 'BODY')
    if body_elements:
        body = body_elements[0]
        rect = body['rect']
        print(f"\n【BODY】")
        print(f"  x: {rect['x']:.2f}px, y: {rect['y']:.2f}px")
        print(f"  width: {rect['width']:.2f}px, height: {rect['height']:.2f}px")
        print(f"  (getBoundingClientRect 返回的是 border box)")
    
    # 3. 第一个 H1
    h1_elements = find_elements(data, 'H1', None, 'ZBrowser功能测试页面')
    if h1_elements:
        h1 = h1_elements[0]
        rect = h1['rect']
        print(f"\n【第一个 H1 - ZBrowser功能测试页面】")
        print(f"  x: {rect['x']:.2f}px, y: {rect['y']:.2f}px")
        print(f"  width: {rect['width']:.2f}px, height: {rect['height']:.2f}px")
        print(f"  (getBoundingClientRect 返回的是 border box)")
        print(f"  计算 content box:")
        print(f"    content.x = border.x + border.left = {rect['x']:.2f} + 2 = {rect['x'] + 2:.2f}px")
        print(f"    content.y = border.y + border.top = {rect['y']:.2f} + 2 = {rect['y'] + 2:.2f}px")
        print(f"    content.width = border.width - border.horizontal = {rect['width']:.2f} - 4 = {rect['width'] - 4:.2f}px")
        print(f"    content.height = border.height - border.vertical = {rect['height']:.2f} - 4 = {rect['height'] - 4:.2f}px")
    
    # 4. block-test
    block_test_elements = find_elements(data, 'DIV', 'block-test')
    if block_test_elements:
        block_test = block_test_elements[0]
        rect = block_test['rect']
        print(f"\n【block-test DIV】")
        print(f"  x: {rect['x']:.2f}px, y: {rect['y']:.2f}px")
        print(f"  width: {rect['width']:.2f}px, height: {rect['height']:.2f}px")
        print(f"  (getBoundingClientRect 返回的是 border box)")
        print(f"  计算 content box:")
        print(f"    content.x = border.x + border.left + padding.left = {rect['x']:.2f} + 2 + 15 = {rect['x'] + 2 + 15:.2f}px")
        print(f"    content.y = border.y + border.top + padding.top = {rect['y']:.2f} + 2 + 15 = {rect['y'] + 2 + 15:.2f}px")
        print(f"    content.width = border.width - border.horizontal - padding.horizontal = {rect['width']:.2f} - 4 - 30 = {rect['width'] - 4 - 30:.2f}px")
        print(f"    content.height = border.height - border.vertical - padding.vertical = {rect['height']:.2f} - 4 - 30 = {rect['height'] - 4 - 30:.2f}px")
    
    # 5. 计算间距
    if h1_elements and block_test_elements:
        h1_rect = h1_elements[0]['rect']
        block_test_rect = block_test_elements[0]['rect']
        h1_bottom = h1_rect['y'] + h1_rect['height']
        block_test_top = block_test_rect['y']
        spacing = block_test_top - h1_bottom
        print(f"\n【H1 和 block-test 之间的间距】")
        print(f"  h1 border box bottom: {h1_bottom:.2f}px")
        print(f"  block-test border box top: {block_test_top:.2f}px")
        print(f"  间距: {spacing:.2f}px")
        print(f"  (应该是 h1 的 margin-bottom = 21.44px)")

if __name__ == "__main__":
    print_comparison()



