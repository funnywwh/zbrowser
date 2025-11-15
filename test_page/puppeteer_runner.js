const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

async function run() {
    const htmlFilePath = process.argv[2];
    const outputDir = process.argv[3];

    if (!htmlFilePath || !outputDir) {
        console.error('Usage: node puppeteer_runner.js <html_file> <output_dir>');
        process.exit(1);
    }

    const browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    try {
        const page = await browser.newPage();
        
        // 设置视口大小（匹配ZBrowser的980x8000）
        await page.setViewport({
            width: 980,
            height: 8000,
            deviceScaleFactor: 1
        });

        // 加载HTML文件
        const htmlContent = fs.readFileSync(htmlFilePath, 'utf-8');
        await page.setContent(htmlContent, { waitUntil: 'networkidle0' });

        // 等待页面渲染完成
        await new Promise(resolve => setTimeout(resolve, 100));

        // 获取body的第一个子元素（我们测试的元素）
        const element = await page.evaluate(() => {
            const body = document.body;
            if (!body || !body.firstElementChild) {
                return null;
            }
            return body.firstElementChild;
        });

        if (!element) {
            console.error('No element found in body');
            process.exit(1);
        }

        // 获取元素的box信息
        const boxInfo = await page.evaluate((elementSelector) => {
            const el = document.body.firstElementChild;
            if (!el) return null;

            const rect = el.getBoundingClientRect();
            const styles = window.getComputedStyle(el);

            // 解析padding
            const paddingTop = parseFloat(styles.paddingTop) || 0;
            const paddingRight = parseFloat(styles.paddingRight) || 0;
            const paddingBottom = parseFloat(styles.paddingBottom) || 0;
            const paddingLeft = parseFloat(styles.paddingLeft) || 0;

            // 解析border
            const borderTop = parseFloat(styles.borderTopWidth) || 0;
            const borderRight = parseFloat(styles.borderRightWidth) || 0;
            const borderBottom = parseFloat(styles.borderBottomWidth) || 0;
            const borderLeft = parseFloat(styles.borderLeftWidth) || 0;

            // 解析margin
            const marginTop = parseFloat(styles.marginTop) || 0;
            const marginRight = parseFloat(styles.marginRight) || 0;
            const marginBottom = parseFloat(styles.marginBottom) || 0;
            const marginLeft = parseFloat(styles.marginLeft) || 0;

            // getBoundingClientRect返回的是border box
            const borderBox = {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height
            };

            // 计算content box
            const contentBox = {
                x: borderBox.x + borderLeft + paddingLeft,
                y: borderBox.y + borderTop + paddingTop,
                width: borderBox.width - borderLeft - borderRight - paddingLeft - paddingRight,
                height: borderBox.height - borderTop - borderBottom - paddingTop - paddingBottom
            };

            return {
                content_box: contentBox,
                border_box: borderBox,
                padding: {
                    top: paddingTop,
                    right: paddingRight,
                    bottom: paddingBottom,
                    left: paddingLeft
                },
                border: {
                    top: borderTop,
                    right: borderRight,
                    bottom: borderBottom,
                    left: borderLeft
                },
                margin: {
                    top: marginTop,
                    right: marginRight,
                    bottom: marginBottom,
                    left: marginLeft
                }
            };
        });

        if (!boxInfo) {
            console.error('Failed to get box info');
            process.exit(1);
        }

        // 保存box信息到JSON文件
        const boxInfoPath = path.join(outputDir, 'puppeteer_box.json');
        fs.writeFileSync(boxInfoPath, JSON.stringify(boxInfo, null, 2));

        // 保存截图
        const screenshotPath = path.join(outputDir, 'puppeteer.png');
        await page.screenshot({
            path: screenshotPath,
            fullPage: true
        });

        console.log('Puppeteer rendering completed');
        console.log(`Box info saved to: ${boxInfoPath}`);
        console.log(`Screenshot saved to: ${screenshotPath}`);

    } finally {
        await browser.close();
    }
}

run().catch((error) => {
    console.error('Error:', error);
    process.exit(1);
});

