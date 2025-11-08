# CSS LR 解析器设计文档

## 1. 概述

采用 LR(1) 语法分析器替代手写递归下降解析器，使用 Zig 的 `comptime` 特性在编译时生成解析表，提升解析性能和代码可维护性。

## 2. CSS 语法规则（BNF）

### 2.1 样式表语法

```
stylesheet ::= rule* | at_rule*
rule ::= selector_list '{' declaration_list '}'
selector_list ::= selector (',' selector)*
selector ::= selector_sequence (combinator selector_sequence)*
selector_sequence ::= simple_selector+
simple_selector ::= type_selector | class_selector | id_selector | attribute_selector | pseudo_selector | universal_selector
combinator ::= ' ' | '>' | '+' | '~'
declaration_list ::= declaration (';' declaration)* ';'?
declaration ::= property ':' value important?
property ::= ident
value ::= keyword | length | color | string | number | percentage | function_call
```

### 2.2 Token 类型

- `ident`: 标识符
- `string`: 字符串
- `number`: 数字
- `percentage`: 百分比
- `dimension`: 带单位的数字
- `hash`: #颜色或ID
- `function`: 函数
- `at_keyword`: @规则
- `delim`: 分隔符（{, }, :, ;, ,, (, ), [, ]）
- `whitespace`: 空白字符
- `comment`: 注释
- `eof`: 文件结束

## 3. LR 解析表生成

### 3.1 状态定义

使用 `comptime` 生成 LR 状态和转换表：

```zig
const Action = enum {
    shift,
    reduce,
    accept,
    error,
};

const ParseAction = union(Action) {
    shift: usize,      // 转移到状态
    reduce: usize,     // 归约规则编号
    accept: void,      // 接受
    error: void,       // 错误
};
```

### 3.2 Comptime 表生成

使用 `comptime` 函数生成解析表，避免运行时开销：

```zig
fn generateParseTable(comptime grammar: Grammar) ParseTable {
    // 在编译时生成 LR 解析表
    comptime {
        // 构建 LR 自动机
        // 生成 ACTION 和 GOTO 表
    }
}
```

## 4. LR 解析器实现

### 4.1 解析器结构

```zig
pub const LRParser = struct {
    tokenizer: tokenizer.Tokenizer,
    allocator: std.mem.Allocator,
    state_stack: std.ArrayList(usize),
    symbol_stack: std.ArrayList(Symbol),
    current_token: ?tokenizer.Token,
    
    const Self = @This();
    
    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self {
        return .{
            .tokenizer = tokenizer.Tokenizer.init(input, allocator),
            .allocator = allocator,
            .state_stack = std.ArrayList(usize).init(allocator),
            .symbol_stack = std.ArrayList(Symbol).init(allocator),
            .current_token = null,
        };
    }
    
    pub fn parse(self: *Self) !Stylesheet {
        // LR 解析主循环
    }
};
```

### 4.2 解析算法

1. **初始化**：将初始状态压入状态栈
2. **主循环**：
   - 查看当前 token
   - 查找 ACTION[state][token]
   - 执行动作（shift/reduce/accept/error）
3. **Shift**：将 token 压入符号栈，新状态压入状态栈
4. **Reduce**：根据规则归约，弹出符号和状态，压入新的非终结符
5. **Accept**：解析成功
6. **Error**：报告错误

## 5. 优势

1. **性能**：解析表在编译时生成，运行时只需查表，性能优于递归下降
2. **可维护性**：语法规则集中定义，易于修改和扩展
3. **正确性**：LR 解析器保证解析的正确性和一致性
4. **可扩展性**：添加新语法规则只需修改语法定义

## 6. 实现计划

1. 定义 CSS 语法规则（BNF）
2. 实现 comptime LR 表生成器
3. 实现 LR 解析器核心算法
4. 迁移现有解析逻辑到新解析器
5. 保持 API 兼容性
6. 添加测试确保功能正确


