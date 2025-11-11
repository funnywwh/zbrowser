// 输出结构化的 Chrome 计算后样式 JSON
// 包含元素标识信息（tagName, className, id, textContent等）
// 格式：{ element: {...}, styles: {...} }

(() => {
  const elements = [];

  const skip = ['SCRIPT', 'STYLE', 'LINK', 'META']; // 可选过滤

  // 遍历所有元素
  document.querySelectorAll('*').forEach((el, index) => {
    if (skip.includes(el.tagName)) return;

    const style = getComputedStyle(el);

    // 构建元素标识信息
    const elementInfo = {
      index: index,
      tagName: el.tagName,
      className: el.className || '',
      id: el.id || '',
      textContent: el.textContent ? el.textContent.trim().substring(0, 100) : '', // 只取前100个字符
      // 父元素信息
      parentTagName: el.parentElement ? el.parentElement.tagName : '',
      parentClassName: el.parentElement ? (el.parentElement.className || '') : '',
      parentId: el.parentElement ? (el.parentElement.id || '') : '',
      // 子元素数量
      childElementCount: el.childElementCount,
      // 关键样式属性（用于快速识别）
      keyStyles: {
        width: style.getPropertyValue('width'),
        height: style.getPropertyValue('height'),
        backgroundColor: style.getPropertyValue('background-color'),
        color: style.getPropertyValue('color'),
        fontSize: style.getPropertyValue('font-size'),
        marginTop: style.getPropertyValue('margin-top'),
        marginBottom: style.getPropertyValue('margin-bottom'),
        paddingTop: style.getPropertyValue('padding-top'),
        paddingBottom: style.getPropertyValue('padding-bottom'),
        borderTopWidth: style.getPropertyValue('border-top-width')
      }
    };

    // 构建完整样式对象
    const styles = {};
    for (let i = 0; i < style.length; i++) {
      const key = style[i];
      styles[key] = style.getPropertyValue(key);
    }

    // 组合元素信息和样式
    elements.push({
      element: elementInfo,
      styles: styles
    });
  });

  // 下载为 JSON 文件
  const blob = new Blob([JSON.stringify(elements, null, 2)], {type: 'application/json'});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'computed-styles-structured.json';
  a.click();
  
  console.log(`✓ Exported ${elements.length} elements to computed-styles-structured.json`);
  console.log(`  File will be downloaded automatically.`);
})();

