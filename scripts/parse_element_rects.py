#!/usr/bin/env python3
"""
解析 element-rects.json 文件，显示元素的矩形区域信息
"""

import json
import sys

def parse_rect_file(json_file_path):
    """解析 element-rects.json 文件"""
    with open(json_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    return data

def find_element_rects(data, tag_name=None, class_name=None, text_content_substring=None):
    """查找匹配的元素"""
    found_elements = []
    for item in data:
        element_info = item['element']
        rect = item['rect']

        match = True
        if tag_name and element_info['tagName'].lower() != tag_name.lower():
            match = False
        if class_name and class_name not in element_info['className'].split():
            match = False
        if text_content_substring and text_content_substring not in element_info['textContent']:
            match = False

        if match:
            found_elements.append({'element_info': element_info, 'rect': rect})
    return found_elements

def print_element_rect(element_data, title):
    """打印元素的矩形区域信息"""
    print(f"\n=== {title} ===")
    element_info = element_data['element_info']
    rect = element_data['rect']

    print(f"  Tag: {element_info['tagName']}")
    if element_info['className']:
        print(f"  Class: {element_info['className']}")
    if element_info['id']:
        print(f"  ID: {element_info['id']}")
    if element_info['textContent']:
        print(f"  Text Content: {element_info['textContent']}")
    print(f"  Parent Tag: {element_info['parentTagName']}")
    print(f"  Parent Class: {element_info['parentClassName']}")
    print(f"  Is Visible: {element_info['isVisible']}")
    
    print(f"\n  Page Coordinates (absolute):")
    print(f"    x: {rect['x']:.2f}px")
    print(f"    y: {rect['y']:.2f}px")
    print(f"    width: {rect['width']:.2f}px")
    print(f"    height: {rect['height']:.2f}px")
    print(f"    top: {rect['top']:.2f}px")
    print(f"    right: {rect['right']:.2f}px")
    print(f"    bottom: {rect['bottom']:.2f}px")
    print(f"    left: {rect['left']:.2f}px")
    
    print(f"\n  Viewport Coordinates (relative to viewport):")
    print(f"    viewportX: {rect['viewportX']:.2f}px")
    print(f"    viewportY: {rect['viewportY']:.2f}px")
    print(f"    viewportTop: {rect['viewportTop']:.2f}px")
    print(f"    viewportRight: {rect['viewportRight']:.2f}px")
    print(f"    viewportBottom: {rect['viewportBottom']:.2f}px")
    print(f"    viewportLeft: {rect['viewportLeft']:.2f}px")

def compare_with_zbrowser(rect_data, zbrowser_output):
    """比较 Chrome 的矩形区域和 ZBrowser 的输出"""
    # 这里可以添加比较逻辑
    pass

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 parse_element_rects.py <json_file_path> [tag_name] [class_name] [text_content]")
        print("\nExamples:")
        print("  python3 parse_element_rects.py element-rects.json")
        print("  python3 parse_element_rects.py element-rects.json h1")
        print("  python3 parse_element_rects.py element-rects.json div block-test")
        print("  python3 parse_element_rects.py element-rects.json h1 '' 'ZBrowser功能测试页面'")
        sys.exit(1)

    json_file_path = sys.argv[1]
    tag_name = sys.argv[2] if len(sys.argv) > 2 else None
    class_name = sys.argv[3] if len(sys.argv) > 3 else None
    text_content = sys.argv[4] if len(sys.argv) > 4 else None

    data = parse_rect_file(json_file_path)
    print(f"Total elements: {len(data)}")

    if tag_name or class_name or text_content:
        # 查找特定元素
        found_elements = find_element_rects(data, tag_name, class_name, text_content)
        if found_elements:
            for i, element_data in enumerate(found_elements):
                title = f"Element {i+1}"
                if element_data['element_info']['className']:
                    title += f" ({element_data['element_info']['className']})"
                print_element_rect(element_data, title)
        else:
            print(f"No elements found matching criteria.")
    else:
        # 显示所有元素（限制数量）
        print(f"\nShowing first 10 elements (use filters to find specific elements):")
        for i, item in enumerate(data[:10]):
            element_info = item['element_info']
            rect = item['rect']
            title = f"{element_info['tagName']}"
            if element_info['className']:
                title += f".{element_info['className'].split()[0]}"
            if element_info['id']:
                title += f"#{element_info['id']}"
            print(f"\n{i+1}. {title}")
            print(f"   Page: ({rect['x']:.1f}, {rect['y']:.1f}) size: {rect['width']:.1f}x{rect['height']:.1f}")
            print(f"   Visible: {element_info['isVisible']}")



