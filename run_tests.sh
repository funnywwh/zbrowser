#!/bin/bash
# 运行测试并将输出保存到日志文件

# 初始化环境
source env.sh

# 创建日志目录
mkdir -p logs

# 使用固定的日志文件名
LOG_FILE="logs/test_output.log"
FAILED_LOG="logs/test_failed.log"

# 运行测试并将输出保存到日志文件
echo "运行测试并将输出保存到: $LOG_FILE"
zig build test 2>&1 | tee "$LOG_FILE"

# 提取失败信息到单独的文件
echo "提取失败测试信息到: $FAILED_LOG"
grep -A 10 "failed\|error:" "$LOG_FILE" > "$FAILED_LOG" 2>/dev/null || echo "没有找到失败的测试"

echo ""
echo "测试完成！"
echo "完整日志: $LOG_FILE"
echo "失败信息: $FAILED_LOG"

