// 测试getBoundingClientRect返回的是border box还是content box
const h1 = document.querySelector('h1');
if (h1) {
  const rect = h1.getBoundingClientRect();
  const styles = window.getComputedStyle(h1);
  const borderLeft = parseFloat(styles.borderLeftWidth) || 0;
  const borderRight = parseFloat(styles.borderRightWidth) || 0;
  const paddingLeft = parseFloat(styles.paddingLeft) || 0;
  const paddingRight = parseFloat(styles.paddingRight) || 0;
  const contentWidth = parseFloat(styles.width) || 0;
  const contentHeight = parseFloat(styles.height) || 0;
  
  console.log('=== H1 getBoundingClientRect() 测试 ===');
  console.log('');
  console.log('getBoundingClientRect() 返回值:');
  console.log('  x (left):', rect.left);
  console.log('  y (top):', rect.top);
  console.log('  width:', rect.width);
  console.log('  height:', rect.height);
  console.log('  right:', rect.right);
  console.log('  bottom:', rect.bottom);
  console.log('');
  console.log('Computed Styles:');
  console.log('  width (content):', styles.width, '=', contentWidth);
  console.log('  height (content):', styles.height, '=', contentHeight);
  console.log('  padding-left:', styles.paddingLeft, '=', paddingLeft);
  console.log('  padding-right:', styles.paddingRight, '=', paddingRight);
  console.log('  border-left-width:', styles.borderLeftWidth, '=', borderLeft);
  console.log('  border-right-width:', styles.borderRightWidth, '=', borderRight);
  console.log('');
  console.log('=== 验证 width ===');
  const expectedBorderBoxWidth = contentWidth + paddingLeft + paddingRight + borderLeft + borderRight;
  console.log('  content width:', contentWidth);
  console.log('  padding (left + right):', paddingLeft + paddingRight);
  console.log('  border (left + right):', borderLeft + borderRight);
  console.log('  expected border box width:', expectedBorderBoxWidth);
  console.log('  actual rect.width:', rect.width);
  console.log('  match:', Math.abs(rect.width - expectedBorderBoxWidth) < 0.1, 
              '(差值:', Math.abs(rect.width - expectedBorderBoxWidth), ')');
  console.log('');
  console.log('=== 验证 x 位置 ===');
  console.log('如果 rect.left 是 border box 的位置:');
  console.log('  content box x 应该是:', rect.left + paddingLeft + borderLeft);
  console.log('');
  console.log('如果 rect.left 是 content box 的位置:');
  console.log('  border box x 应该是:', rect.left - paddingLeft - borderLeft);
  console.log('');
  console.log('=== 结论 ===');
  if (Math.abs(rect.width - expectedBorderBoxWidth) < 0.1) {
    console.log('✓ rect.width 是 border box 的 width');
    console.log('  因此 rect.left 也应该是 border box 的 x 位置');
    console.log('  即: rect.left = border box x =', rect.left);
    console.log('  content box x =', rect.left + paddingLeft + borderLeft);
  } else {
    console.log('✗ rect.width 不是 border box 的 width');
  }
}

