// 获取所有元素的矩形区域（页面坐标）
// 输出结构化的 JSON 格式，包含元素标识信息和矩形区域信息

(() => {
  const elements = [];

  const skip = ['SCRIPT', 'STYLE', 'LINK', 'META']; // 可选过滤

  // 遍历所有元素
  document.querySelectorAll('*').forEach((el, index) => {
    if (skip.includes(el.tagName)) return;

    // 获取元素的矩形区域（相对于视口）
    const rect = el.getBoundingClientRect();
    
    // 获取滚动位置（用于转换为页面坐标）
    const scrollX = window.pageXOffset || document.documentElement.scrollLeft || 0;
    const scrollY = window.pageYOffset || document.documentElement.scrollTop || 0;

    // 转换为页面坐标（绝对坐标）
    const pageRect = {
      // 相对于页面的坐标（包括滚动）
      x: rect.left + scrollX,
      y: rect.top + scrollY,
      // 相对于视口的坐标（原始 getBoundingClientRect）
      viewportX: rect.left,
      viewportY: rect.top,
      // 尺寸
      width: rect.width,
      height: rect.height,
      // 边界框信息
      top: rect.top + scrollY,
      right: rect.right + scrollX,
      bottom: rect.bottom + scrollY,
      left: rect.left + scrollX,
      // 视口边界框信息
      viewportTop: rect.top,
      viewportRight: rect.right,
      viewportBottom: rect.bottom,
      viewportLeft: rect.left
    };

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
      // 样式信息（用于快速识别）
      display: getComputedStyle(el).display,
      position: getComputedStyle(el).position,
      // 是否可见
      isVisible: rect.width > 0 && rect.height > 0 && 
                 getComputedStyle(el).visibility !== 'hidden' &&
                 getComputedStyle(el).display !== 'none'
    };

    // 组合元素信息和矩形区域
    elements.push({
      element: elementInfo,
      rect: pageRect
    });
  });

  // 输出为 JSON 格式
  const jsonData = JSON.stringify(elements, null, 2);
  
  // 下载为 JSON 文件
  const blob = new Blob([jsonData], {type: 'application/json'});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'element-rects.json';
  a.click();
  
  console.log(`✓ Exported ${elements.length} elements to element-rects.json`);
  console.log(`  File will be downloaded automatically.`);
  console.log(`\nSample data structure:`);
  if (elements.length > 0) {
    console.log(JSON.stringify(elements[0], null, 2));
  }
})();



