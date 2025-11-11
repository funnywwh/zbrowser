#!/usr/bin/env python3
"""
对比 Chrome 的 element-rects.json 和 ZBrowser 的输出
"""

import json
import sys
import re

def parse_zbrowser_output(output_text):
    """解析 ZBrowser 的输出，提取元素的位置和尺寸信息"""
    elements = {}
    
    lines = output_text.split('\n')
    i = 0
    current_tag = None
    current_class = None
    
    while i < len(lines):
        line = lines[i].strip()
        
        # 匹配 "Tag: h1" 或 "Tag: div"
        if line.startswith('Tag:'):
            tag_match = re.match(r'Tag:\s*(\w+)', line)
            if tag_match:
                current_tag = tag_match.group(1)
                current_class = None
                i += 1
                continue
        
        # 匹配 "Class: block-test"
        if line.startswith('Class:'):
            class_match = re.match(r'Class:\s*([^\s]+)', line)
            if class_match:
                current_class = class_match.group(1)
                i += 1
                continue
        
        # 匹配 "Content: x=20.00, y=61.44, width=921.00, height=46.00"
        if line.startswith('Content:') and current_tag:
            content_match = re.match(r'Content:\s*x=([\d.]+),\s*y=([\d.]+),\s+width=([\d.]+),\s+height=([\d.]+)', line)
            if content_match:
                x = float(content_match.group(1))
                y = float(content_match.group(2))
                width = float(content_match.group(3))
                height = float(content_match.group(4))
                
                # 创建唯一标识
                key = f"{current_tag.lower()}"
                if current_class:
                    key += f".{current_class}"
                
                elements[key] = {
                    'tag': current_tag,
                    'class': current_class or '',
                    'content': {
                        'x': x,
                        'y': y,
                        'width': width,
                        'height': height
                    }
                }
        
        i += 1
    
    return elements

def find_chrome_element(data, tag_name, class_name=None, text_content_substring=None):
    """在 Chrome 数据中查找元素"""
    for item in data:
        elem = item['element']
        if elem['tagName'].lower() != tag_name.lower():
            continue
        if class_name and class_name not in elem['className'].split():
            continue
        if text_content_substring and text_content_substring not in elem['textContent']:
            continue
        return item
    return None

def compare_elements(chrome_data, zbrowser_data):
    """对比 Chrome 和 ZBrowser 的元素位置"""
    print("=" * 80)
    print("Chrome vs ZBrowser 元素位置对比")
    print("=" * 80)
    
    # 对比第一个 h1
    chrome_h1 = find_chrome_element(chrome_data, 'H1', None, 'ZBrowser功能测试页面')
    if chrome_h1:
        chrome_rect = chrome_h1['rect']
        print(f"\n【第一个 H1 - ZBrowser功能测试页面】")
        print(f"Chrome (getBoundingClientRect - border box):")
        print(f"  x: {chrome_rect['x']:.2f}px, y: {chrome_rect['y']:.2f}px")
        print(f"  width: {chrome_rect['width']:.2f}px, height: {chrome_rect['height']:.2f}px")
        
        # 查找 ZBrowser 的 h1（第一个，没有 class，且 y 坐标应该较小）
        zbrowser_h1 = None
        min_y = float('inf')
        for key, elem in zbrowser_data.items():
            if elem['tag'].lower() == 'h1' and not elem['class']:
                if elem['content']['y'] < min_y:
                    min_y = elem['content']['y']
                    zbrowser_h1 = elem
        
        if zbrowser_h1:
            zb_rect = zbrowser_h1['content']
            print(f"ZBrowser (content box):")
            print(f"  x: {zb_rect['x']:.2f}px, y: {zb_rect['y']:.2f}px")
            print(f"  width: {zb_rect['width']:.2f}px, height: {zb_rect['height']:.2f}px")
            
            # Chrome 的 getBoundingClientRect 返回的是 border box
            # ZBrowser 的 content 是 content box
            # 需要转换对比
            # Chrome border box: x=20, y=41.44, width=925, height=50
            # ZBrowser content box: x=20, y=61.44, width=921, height=46
            # ZBrowser border box 应该是: x=20-0-2=18, y=61.44-0-2=59.44, width=921+0+4=925, height=46+0+4=50
            zb_border_x = zb_rect['x'] - 0 - 2  # content.x - padding.left - border.left
            zb_border_y = zb_rect['y'] - 0 - 2  # content.y - padding.top - border.top
            zb_border_width = zb_rect['width'] + 0 + 4  # content.width + padding.horizontal + border.horizontal
            zb_border_height = zb_rect['height'] + 0 + 4  # content.height + padding.vertical + border.vertical
            
            print(f"\nZBrowser (border box - 计算值):")
            print(f"  x: {zb_border_x:.2f}px, y: {zb_border_y:.2f}px")
            print(f"  width: {zb_border_width:.2f}px, height: {zb_border_height:.2f}px")
            
            print(f"\n差异 (Chrome - ZBrowser border box):")
            print(f"  x: {chrome_rect['x'] - zb_border_x:.2f}px")
            print(f"  y: {chrome_rect['y'] - zb_border_y:.2f}px")
            print(f"  width: {chrome_rect['width'] - zb_border_width:.2f}px")
            print(f"  height: {chrome_rect['height'] - zb_border_height:.2f}px")
        else:
            print("ZBrowser: 未找到")
    
    # 对比 block-test
    chrome_block_test = find_chrome_element(chrome_data, 'DIV', 'block-test')
    if chrome_block_test:
        chrome_rect = chrome_block_test['rect']
        print(f"\n【block-test DIV】")
        print(f"Chrome (getBoundingClientRect - border box):")
        print(f"  x: {chrome_rect['x']:.2f}px, y: {chrome_rect['y']:.2f}px")
        print(f"  width: {chrome_rect['width']:.2f}px, height: {chrome_rect['height']:.2f}px")
        
        # 查找 ZBrowser 的 block-test
        zbrowser_block_test = zbrowser_data.get('div.block-test')
        if zbrowser_block_test:
            zb_rect = zbrowser_block_test['content']
            print(f"ZBrowser (content box):")
            print(f"  x: {zb_rect['x']:.2f}px, y: {zb_rect['y']:.2f}px")
            print(f"  width: {zb_rect['width']:.2f}px, height: {zb_rect['height']:.2f}px")
            
            # block-test 的 padding: 15px, border: 2px
            zb_border_x = zb_rect['x'] - 15 - 2  # content.x - padding.left - border.left
            zb_border_y = zb_rect['y'] - 15 - 2  # content.y - padding.top - border.top
            zb_border_width = zb_rect['width'] + 30 + 4  # content.width + padding.horizontal + border.horizontal
            zb_border_height = zb_rect['height'] + 30 + 4  # content.height + padding.vertical + border.vertical
            
            print(f"\nZBrowser (border box - 计算值):")
            print(f"  x: {zb_border_x:.2f}px, y: {zb_border_y:.2f}px")
            print(f"  width: {zb_border_width:.2f}px, height: {zb_border_height:.2f}px")
            
            print(f"\n差异 (Chrome - ZBrowser border box):")
            print(f"  x: {chrome_rect['x'] - zb_border_x:.2f}px")
            print(f"  y: {chrome_rect['y'] - zb_border_y:.2f}px")
            print(f"  width: {chrome_rect['width'] - zb_border_width:.2f}px")
            print(f"  height: {chrome_rect['height'] - zb_border_height:.2f}px")
        else:
            print("ZBrowser: 未找到")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 compare_rects.py <element-rects.json> [zbrowser_output.txt]")
        print("\n如果没有提供 zbrowser_output.txt，将从标准输入读取 ZBrowser 输出")
        sys.exit(1)
    
    json_file = sys.argv[1]
    
    # 读取 Chrome 数据
    with open(json_file, 'r', encoding='utf-8') as f:
        chrome_data = json.load(f)
    
    # 读取 ZBrowser 输出
    if len(sys.argv) > 2:
        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            zbrowser_output = f.read()
    else:
        zbrowser_output = sys.stdin.read()
    
    # 解析 ZBrowser 输出
    zbrowser_data = parse_zbrowser_output(zbrowser_output)
    
    # 对比
    compare_elements(chrome_data, zbrowser_data)
