#!/usr/bin/env python3
"""
解析结构化的 Chrome 样式 JSON 文件
用法: python3 parse_structured_styles.py computed-styles-structured.json
"""

import json
import sys

def find_element(elements, tag_name=None, class_name=None, id_name=None, parent_class=None):
    """查找匹配的元素"""
    results = []
    for item in elements:
        elem = item.get('element', {})
        match = True
        
        if tag_name and elem.get('tagName') != tag_name:
            match = False
        if class_name and class_name not in elem.get('className', ''):
            match = False
        if id_name and elem.get('id') != id_name:
            match = False
        if parent_class and parent_class not in elem.get('parentClassName', ''):
            match = False
            
        if match:
            results.append(item)
    
    return results

def print_element_info(item):
    """打印元素信息"""
    elem = item.get('element', {})
    styles = item.get('styles', {})
    key_styles = elem.get('keyStyles', {})
    
    print(f"\n=== Element {elem.get('index', '?')} ===")
    print(f"Tag: {elem.get('tagName', 'N/A')}")
    if elem.get('className'):
        print(f"Class: {elem.get('className')}")
    if elem.get('id'):
        print(f"ID: {elem.get('id')}")
    if elem.get('textContent'):
        print(f"Text: {elem.get('textContent')[:50]}...")
    print(f"Parent: {elem.get('parentTagName', 'N/A')} {elem.get('parentClassName', '')}")
    
    print(f"\nKey Styles:")
    print(f"  width: {key_styles.get('width', 'N/A')}")
    print(f"  height: {key_styles.get('height', 'N/A')}")
    print(f"  margin-top: {key_styles.get('marginTop', 'N/A')}")
    print(f"  margin-bottom: {key_styles.get('marginBottom', 'N/A')}")
    print(f"  padding-top: {key_styles.get('paddingTop', 'N/A')}")
    print(f"  padding-bottom: {key_styles.get('paddingBottom', 'N/A')}")
    print(f"  background-color: {key_styles.get('backgroundColor', 'N/A')}")
    print(f"  color: {key_styles.get('color', 'N/A')}")
    print(f"  font-size: {key_styles.get('fontSize', 'N/A')}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 parse_structured_styles.py <json_file>")
        sys.exit(1)
    
    json_file = sys.argv[1]
    
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        print(f"Total elements: {len(data)}")
        
        # 示例：查找 block-test div
        print("\n" + "="*50)
        print("Finding block-test div...")
        block_test = find_element(data, tag_name='DIV', class_name='block-test')
        if block_test:
            print_element_info(block_test[0])
        
        # 示例：查找 block-test 内的 h1
        print("\n" + "="*50)
        print("Finding h1 inside block-test...")
        h1_in_block_test = find_element(data, tag_name='H1', parent_class='block-test')
        if h1_in_block_test:
            print_element_info(h1_in_block_test[0])
        
        # 示例：查找 block-test 内的 p
        print("\n" + "="*50)
        print("Finding p elements inside block-test...")
        p_in_block_test = find_element(data, tag_name='P', parent_class='block-test')
        for p in p_in_block_test:
            print_element_info(p)
        
        # 示例：查找 block-test 内的 div
        print("\n" + "="*50)
        print("Finding div inside block-test...")
        div_in_block_test = find_element(data, tag_name='DIV', parent_class='block-test')
        if div_in_block_test:
            print_element_info(div_in_block_test[0])
            
    except FileNotFoundError:
        print(f"Error: File '{json_file}' not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON file: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

