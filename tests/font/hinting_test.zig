const std = @import("std");
const testing = std.testing;
const hinting = @import("hinting");
const ttf = @import("ttf");

// 测试HintingInterpreter初始化和清理
test "HintingInterpreter init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    interpreter.deinit();

    // 测试：解释器应该可以正常初始化和清理
    // 没有返回值，只要不崩溃即可
}

// 测试HintingInterpreter边界情况 - 空分配器
test "HintingInterpreter boundary - empty allocator" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    // 测试：空分配器应该正常工作（使用GPA）
    try testing.expect(interpreter.cvt.items.len == 0);
    try testing.expect(interpreter.storage.items.len == 0);
    try testing.expect(interpreter.stack.items.len == 0);
}

// 测试CVT表加载 - 正常情况
test "HintingInterpreter loadCvt - normal case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    // 创建CVT表数据（每个条目2字节，i16大端序）
    var cvt_data = try allocator.alloc(u8, 6); // 3个条目
    defer allocator.free(cvt_data);

    std.mem.writeInt(i16, cvt_data[0..2], 100, .big);
    std.mem.writeInt(i16, cvt_data[2..4], 200, .big);
    std.mem.writeInt(i16, cvt_data[4..6], 300, .big);

    try interpreter.loadCvt(cvt_data);

    // 测试：应该正确加载CVT表
    try testing.expect(interpreter.cvt.items.len == 3);
    try testing.expect(interpreter.cvt.items[0] == 100);
    try testing.expect(interpreter.cvt.items[1] == 200);
    try testing.expect(interpreter.cvt.items[2] == 300);
}

// 测试CVT表加载 - 边界情况：空数据
test "HintingInterpreter loadCvt boundary - empty data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    const empty_data = &[_]u8{};

    // 测试：空数据应该成功加载（空CVT表）
    try interpreter.loadCvt(empty_data);
    try testing.expect(interpreter.cvt.items.len == 0);
}

// 测试CVT表加载 - 边界情况：奇数长度（无效格式）
test "HintingInterpreter loadCvt boundary - odd length" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    const odd_data = &[_]u8{ 0, 1, 2 }; // 3字节，不是2的倍数

    // 测试：奇数长度应该返回错误
    const result = interpreter.loadCvt(odd_data);
    try testing.expectError(error.InvalidFormat, result);
}

// 测试CVT表加载 - 边界情况：单个条目
test "HintingInterpreter loadCvt boundary - single entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var cvt_data = try allocator.alloc(u8, 2);
    defer allocator.free(cvt_data);

    std.mem.writeInt(i16, cvt_data[0..2], -100, .big);

    try interpreter.loadCvt(cvt_data);

    // 测试：应该正确加载单个条目
    try testing.expect(interpreter.cvt.items.len == 1);
    try testing.expect(interpreter.cvt.items[0] == -100);
}

// 测试CVT表加载 - 边界情况：大量条目
test "HintingInterpreter loadCvt boundary - large number of entries" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    const num_entries = 1000;
    var cvt_data = try allocator.alloc(u8, num_entries * 2);
    defer allocator.free(cvt_data);

    var i: usize = 0;
    while (i < num_entries) : (i += 1) {
        std.mem.writeInt(i16, cvt_data[i * 2..][0..2], @as(i16, @intCast(i)), .big);
    }

    try interpreter.loadCvt(cvt_data);

    // 测试：应该正确加载所有条目
    try testing.expect(interpreter.cvt.items.len == num_entries);
    try testing.expect(interpreter.cvt.items[0] == 0);
    try testing.expect(interpreter.cvt.items[999] == 999);
}

// 测试指令执行 - 栈操作：PUSH和POP
test "HintingInterpreter executeInstruction - stack operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    // 创建简单的字形点列表
    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 测试NPUSHB（Push N Bytes）
    var instructions = try allocator.alloc(u8, 5);
    defer allocator.free(instructions);

    instructions[0] = 0x40; // NPUSHB
    instructions[1] = 3; // N = 3
    instructions[2] = 10; // value 1
    instructions[3] = 20; // value 2
    instructions[4] = 30; // value 3

    interpreter.instructions = instructions;
    interpreter.ip = 1; // ip指向N值（instructions[1]）

    // 执行NPUSHB指令（会从ip位置读取N值，然后读取N个字节）
    try interpreter.executeInstruction(0x40, &points, 12.0);

    // 测试：应该将3个值推入栈
    try testing.expect(interpreter.stack.items.len == 3);
    try testing.expect(interpreter.stack.items[0] == 10);
    try testing.expect(interpreter.stack.items[1] == 20);
    try testing.expect(interpreter.stack.items[2] == 30);
}

// 测试指令执行 - 数学运算：ADD
test "HintingInterpreter executeInstruction - ADD operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 先推入两个值
    try interpreter.stack.append(allocator, 10);
    try interpreter.stack.append(allocator, 20);

    // 执行ADD指令（0x60）
    try interpreter.executeInstruction(0x60, &points, 12.0);

    // 测试：应该计算10 + 20 = 30
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 30);
}

// 测试指令执行 - 数学运算：SUB
test "HintingInterpreter executeInstruction - SUB operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    try interpreter.stack.append(allocator, 20);
    try interpreter.stack.append(allocator, 10);

    // 执行SUB指令（0x61）
    try interpreter.executeInstruction(0x61, &points, 12.0);

    // 测试：应该计算20 - 10 = 10
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 10);
}

// 测试指令执行 - 数学运算：MUL
test "HintingInterpreter executeInstruction - MUL operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    try interpreter.stack.append(allocator, 5);
    try interpreter.stack.append(allocator, 6);

    // 执行MUL指令（0x62）
    try interpreter.executeInstruction(0x62, &points, 12.0);

    // 测试：应该计算5 * 6 = 30
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 30);
}

// 测试指令执行 - 数学运算：DIV
test "HintingInterpreter executeInstruction - DIV operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    try interpreter.stack.append(allocator, 20);
    try interpreter.stack.append(allocator, 4);

    // 执行DIV指令（0x63）
    try interpreter.executeInstruction(0x63, &points, 12.0);

    // 测试：应该计算20 / 4 = 5
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 5);
}

// 测试指令执行 - 边界情况：除零
test "HintingInterpreter executeInstruction boundary - division by zero" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    try interpreter.stack.append(allocator, 20);
    try interpreter.stack.append(allocator, 0);

    // 测试：除零应该返回错误
    const result = interpreter.executeInstruction(0x63, &points, 12.0);
    try testing.expectError(error.DivisionByZero, result);
}

// 测试指令执行 - 逻辑运算：LT（小于）
test "HintingInterpreter executeInstruction - LT operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    try interpreter.stack.append(allocator, 5);
    try interpreter.stack.append(allocator, 10);

    // 执行LT指令（0x50）
    try interpreter.executeInstruction(0x50, &points, 12.0);

    // 测试：5 < 10 应该返回1
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 1);

    // 测试：10 < 5 应该返回0
    interpreter.stack.clearRetainingCapacity();
    try interpreter.stack.append(allocator, 10);
    try interpreter.stack.append(allocator, 5);

    try interpreter.executeInstruction(0x50, &points, 12.0);
    try testing.expect(interpreter.stack.items[0] == 0);
}

// 测试指令执行 - 逻辑运算：EQ（等于）
test "HintingInterpreter executeInstruction - EQ operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    try interpreter.stack.append(allocator, 10);
    try interpreter.stack.append(allocator, 10);

    // 执行EQ指令（0x54）
    try interpreter.executeInstruction(0x54, &points, 12.0);

    // 测试：10 == 10 应该返回1
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 1);

    // 测试：10 == 5 应该返回0
    interpreter.stack.clearRetainingCapacity();
    try interpreter.stack.append(allocator, 10);
    try interpreter.stack.append(allocator, 5);

    try interpreter.executeInstruction(0x54, &points, 12.0);
    try testing.expect(interpreter.stack.items[0] == 0);
}

// 测试指令执行 - 图形状态：SVTCA（设置自由向量）
test "HintingInterpreter executeInstruction - SVTCA operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 执行SVTCA[0]（设置为Y轴）
    try interpreter.executeInstruction(0x00, &points, 12.0);

    // 测试：freedom_vector应该设置为Y轴
    try testing.expect(interpreter.graphics_state.freedom_vector.x == 0);
    try testing.expect(interpreter.graphics_state.freedom_vector.y == 1);

    // 执行SVTCA[1]（设置为X轴）
    try interpreter.executeInstruction(0x01, &points, 12.0);

    // 测试：freedom_vector应该设置为X轴
    try testing.expect(interpreter.graphics_state.freedom_vector.x == 1);
    try testing.expect(interpreter.graphics_state.freedom_vector.y == 0);
}

// 测试指令执行 - 图形状态：RTG（Round To Grid）
test "HintingInterpreter executeInstruction - RTG operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 执行RTG指令（0x18）
    try interpreter.executeInstruction(0x18, &points, 12.0);

    // 测试：round_state应该设置为to_grid
    try testing.expect(interpreter.graphics_state.round_state == .to_grid);
}

// 测试指令执行 - 边界情况：栈下溢
test "HintingInterpreter executeInstruction boundary - stack underflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 测试：空栈执行ADD应该返回错误
    const result = interpreter.executeInstruction(0x60, &points, 12.0);
    try testing.expectError(error.StackUnderflow, result);
}

// 测试指令执行 - 边界情况：无效指令
test "HintingInterpreter executeInstruction boundary - invalid instruction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 测试：无效指令（0xFF）应该被忽略（不崩溃）
    try interpreter.executeInstruction(0xFF, &points, 12.0);
    // 只要不崩溃即可
}

// 测试roundValue - 正常情况
test "HintingInterpreter roundValue - normal case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    // 设置round_state为to_grid
    interpreter.graphics_state.round_state = .to_grid;

    // 测试：应该将值对齐到网格
    const rounded = interpreter.roundValue(100);
    // 100 + 32 = 132, 132 / 64 = 2, 2 * 64 = 128
    try testing.expect(rounded == 128);
}

// 测试roundValue - 边界情况：off状态
test "HintingInterpreter roundValue boundary - off state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    interpreter.graphics_state.round_state = .off;

    // 测试：off状态应该返回原值
    const value: i32 = 123;
    const rounded = interpreter.roundValue(value);
    try testing.expect(rounded == value);
}

// 测试executeGlyphInstructions - 正常情况
test "HintingInterpreter executeGlyphInstructions - normal case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 创建简单的指令序列：NPUSHB 3, 10, 20, 30
    var instructions = try allocator.alloc(u8, 5);
    defer allocator.free(instructions);

    instructions[0] = 0x40; // NPUSHB
    instructions[1] = 3; // N = 3
    instructions[2] = 10;
    instructions[3] = 20;
    instructions[4] = 30;

    try interpreter.executeGlyphInstructions(instructions, &points, 12.0, 1000);

    // 测试：应该执行指令并将值推入栈
    try testing.expect(interpreter.stack.items.len == 3);
    try testing.expect(interpreter.stack.items[0] == 10);
    try testing.expect(interpreter.stack.items[1] == 20);
    try testing.expect(interpreter.stack.items[2] == 30);
}

// 测试executeGlyphInstructions - 边界情况：空指令
test "HintingInterpreter executeGlyphInstructions boundary - empty instructions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    const empty_instructions = &[_]u8{};

    // 测试：空指令应该成功执行（不崩溃）
    try interpreter.executeGlyphInstructions(empty_instructions, &points, 12.0, 1000);
    try testing.expect(interpreter.stack.items.len == 0);
}

// 测试loadFpgm和loadPrep - 正常情况（当前是简化实现）
test "HintingInterpreter loadFpgm and loadPrep - normal case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    const fpgm_data = &[_]u8{ 0x40, 0x01, 0x10 }; // 示例指令
    const prep_data = &[_]u8{ 0x18 }; // RTG指令

    // 测试：应该成功加载（当前是简化实现，只存储不执行）
    try interpreter.loadFpgm(fpgm_data);
    try interpreter.loadPrep(prep_data);
    // 只要不崩溃即可
}

// 测试存储区操作：WS和RS
test "HintingInterpreter executeInstruction - storage operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 推入索引和值
    try interpreter.stack.append(allocator, 0); // 索引
    try interpreter.stack.append(allocator, 123); // 值

    // 执行WS指令（0x42 - Write Storage）
    try interpreter.executeInstruction(0x42, &points, 12.0);

    // 测试：应该写入存储区
    try testing.expect(interpreter.storage.items.len >= 1);
    try testing.expect(interpreter.storage.items[0] == 123);

    // 清空栈，推入索引
    interpreter.stack.clearRetainingCapacity();
    try interpreter.stack.append(allocator, 0);

    // 执行RS指令（0x43 - Read Storage）
    try interpreter.executeInstruction(0x43, &points, 12.0);

    // 测试：应该从存储区读取值
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 123);
}

// 测试CVT操作：RCVT和WCVTP
test "HintingInterpreter executeInstruction - CVT operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = hinting.HintingInterpreter.init(allocator);
    defer interpreter.deinit();

    // 先加载CVT表
    var cvt_data = try allocator.alloc(u8, 2);
    defer allocator.free(cvt_data);
    std.mem.writeInt(i16, cvt_data[0..2], 500, .big);
    try interpreter.loadCvt(cvt_data);

    var points = std.ArrayList(ttf.TtfParser.Glyph.Point){};
    defer points.deinit(allocator);

    // 设置instructions为空（RCVT不需要读取instructions）
    interpreter.instructions = &[_]u8{};
    interpreter.ip = 0;

    // 推入索引
    try interpreter.stack.append(allocator, 0);

    // 执行RCVT指令（0x45 - Read Control Value Table）
    try interpreter.executeInstruction(0x45, &points, 12.0);

    // 测试：应该从CVT读取值
    try testing.expect(interpreter.stack.items.len == 1);
    try testing.expect(interpreter.stack.items[0] == 500);

    // 清空栈，推入索引和新值
    interpreter.stack.clearRetainingCapacity();
    try interpreter.stack.append(allocator, 0); // 索引
    try interpreter.stack.append(allocator, 600); // 新值

    // 执行WCVTP指令（0x44 - Write Control Value Table in Pixel units）
    try interpreter.executeInstruction(0x44, &points, 12.0);

    // 测试：应该更新CVT值
    try testing.expect(interpreter.cvt.items[0] == 600);
}

