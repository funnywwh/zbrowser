#!/bin/bash
# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 将项目本地的Zig编译器路径添加到PATH的最前面
export PATH="$SCRIPT_DIR/zig-x86_64-linux-0.15.2:$PATH"

# 验证Zig版本是否为0.15.2
REQUIRED_VERSION="0.15.2"
if command -v zig &> /dev/null; then
    ACTUAL_VERSION=$(zig version 2>/dev/null || echo "")
    if [ "$ACTUAL_VERSION" != "$REQUIRED_VERSION" ]; then
        echo "警告: Zig版本不匹配！" >&2
        echo "  要求版本: $REQUIRED_VERSION" >&2
        echo "  实际版本: $ACTUAL_VERSION" >&2
        echo "  请确保 zig-x86_64-linux-0.15.2/zig 存在且版本正确" >&2
        return 1 2>/dev/null || exit 1
    else
        echo "✓ Zig版本验证通过: $ACTUAL_VERSION"
    fi
else
    echo "错误: 找不到zig命令！" >&2
    echo "  请确保 zig-x86_64-linux-0.15.2/zig 存在" >&2
    return 1 2>/dev/null || exit 1
fi