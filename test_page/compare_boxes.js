const fs = require('fs');
const path = require('path');

const TOLERANCE = 1.0; // 1px误差范围

function compareBoxes(zbrowserBox, puppeteerBox) {
    const calcDiff = (a, b) => Math.abs(a - b);

    const contentXDiff = calcDiff(zbrowserBox.content_box.x, puppeteerBox.content_box.x);
    const contentYDiff = calcDiff(zbrowserBox.content_box.y, puppeteerBox.content_box.y);
    const contentWidthDiff = calcDiff(zbrowserBox.content_box.width, puppeteerBox.content_box.width);
    const contentHeightDiff = calcDiff(zbrowserBox.content_box.height, puppeteerBox.content_box.height);

    const borderXDiff = calcDiff(zbrowserBox.border_box.x, puppeteerBox.border_box.x);
    const borderYDiff = calcDiff(zbrowserBox.border_box.y, puppeteerBox.border_box.y);
    const borderWidthDiff = calcDiff(zbrowserBox.border_box.width, puppeteerBox.border_box.width);
    const borderHeightDiff = calcDiff(zbrowserBox.border_box.height, puppeteerBox.border_box.height);

    const contentBoxMatch = contentXDiff <= TOLERANCE &&
        contentYDiff <= TOLERANCE &&
        contentWidthDiff <= TOLERANCE &&
        contentHeightDiff <= TOLERANCE;

    const borderBoxMatch = borderXDiff <= TOLERANCE &&
        borderYDiff <= TOLERANCE &&
        borderWidthDiff <= TOLERANCE &&
        borderHeightDiff <= TOLERANCE;

    return {
        content_box_match: contentBoxMatch,
        border_box_match: borderBoxMatch,
        content_box_diff: {
            x: contentXDiff,
            y: contentYDiff,
            width: contentWidthDiff,
            height: contentHeightDiff
        },
        border_box_diff: {
            x: borderXDiff,
            y: borderYDiff,
            width: borderWidthDiff,
            height: borderHeightDiff
        }
    };
}

function main() {
    const zbrowserBoxPath = process.argv[2];
    const puppeteerBoxPath = process.argv[3];
    const outputPath = process.argv[4];

    if (!zbrowserBoxPath || !puppeteerBoxPath || !outputPath) {
        console.error('Usage: node compare_boxes.js <zbrowser_box.json> <puppeteer_box.json> <output.json>');
        process.exit(1);
    }

    // 读取box信息
    const zbrowserBox = JSON.parse(fs.readFileSync(zbrowserBoxPath, 'utf-8'));
    const puppeteerBox = JSON.parse(fs.readFileSync(puppeteerBoxPath, 'utf-8'));

    // 对比
    const comparison = compareBoxes(zbrowserBox, puppeteerBox);

    // 保存对比结果
    fs.writeFileSync(outputPath, JSON.stringify(comparison, null, 2));

    console.log('Comparison completed');
    console.log(`Content box match: ${comparison.content_box_match}`);
    console.log(`Border box match: ${comparison.border_box_match}`);
}

main();

