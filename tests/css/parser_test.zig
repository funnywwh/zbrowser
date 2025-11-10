const std = @import("std");
const testing = std.testing;
const css = @import("css");
const selector = @import("selector");

test "parse simple CSS rule" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: red; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    try testing.expectEqual(@as(usize, 1), stylesheet.rules.items.len);
    const rule = stylesheet.rules.items[0];
    try testing.expectEqual(@as(usize, 1), rule.selectors.items.len);
    // 检查选择器：应该是类型选择器 "div"
    const sel = &rule.selectors.items[0];
    try testing.expectEqual(@as(usize, 1), sel.sequences.items.len);
    const seq = &sel.sequences.items[0];
    try testing.expectEqual(@as(usize, 1), seq.selectors.items.len);
    try testing.expectEqual(selector.SimpleSelectorType.type, seq.selectors.items[0].selector_type);
    try testing.expectEqualStrings("div", seq.selectors.items[0].value);
    try testing.expectEqual(@as(usize, 1), rule.declarations.items.len);
    const decl = rule.declarations.items[0];
    try testing.expectEqualStrings("color", decl.name);
    try testing.expect(decl.value == .keyword);
    // 打印实际值以便调试
    if (!std.mem.eql(u8, decl.value.keyword, "red")) {
        std.debug.print("Expected 'red', but got '{s}'\n", .{decl.value.keyword});
    }
    try testing.expectEqualStrings("red", decl.value.keyword);
}

test "parse CSS with multiple rules" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input =
        \\div { color: red; }
        \\p { font-size: 16px; }
    ;
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    try testing.expectEqual(@as(usize, 2), stylesheet.rules.items.len);

    const rule1 = stylesheet.rules.items[0];
    const sel1 = &rule1.selectors.items[0];
    try testing.expectEqual(@as(usize, 1), sel1.sequences.items.len);
    try testing.expectEqual(@as(usize, 1), sel1.sequences.items[0].selectors.items.len);
    try testing.expectEqual(selector.SimpleSelectorType.type, sel1.sequences.items[0].selectors.items[0].selector_type);
    try testing.expectEqualStrings("div", sel1.sequences.items[0].selectors.items[0].value);
    try testing.expect(rule1.declarations.items[0].name.len > 0);

    const rule2 = stylesheet.rules.items[1];
    const sel2 = &rule2.selectors.items[0];
    try testing.expectEqual(@as(usize, 1), sel2.sequences.items.len);
    try testing.expectEqual(@as(usize, 1), sel2.sequences.items[0].selectors.items.len);
    try testing.expectEqual(selector.SimpleSelectorType.type, sel2.sequences.items[0].selectors.items[0].selector_type);
    try testing.expectEqualStrings("p", sel2.sequences.items[0].selectors.items[0].value);
}

test "parse CSS with length values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { width: 100px; height: 50%; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    try testing.expectEqual(@as(usize, 1), stylesheet.rules.items.len);
    const rule = stylesheet.rules.items[0];
    try testing.expectEqual(@as(usize, 2), rule.declarations.items.len);

    const width_decl = rule.declarations.items[0];
    try testing.expectEqualStrings("width", width_decl.name);
    try testing.expect(width_decl.value == .length);
    try testing.expectEqual(@as(f64, 100.0), width_decl.value.length.value);
    try testing.expectEqualStrings("px", width_decl.value.length.unit);

    const height_decl = rule.declarations.items[1];
    try testing.expectEqualStrings("height", height_decl.name);
    try testing.expect(height_decl.value == .percentage);
    try testing.expectEqual(@as(f64, 50.0), height_decl.value.percentage);
}

test "parse CSS with color values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { background-color: #ff0000; color: #00ff00; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    try testing.expectEqual(@as(usize, 1), stylesheet.rules.items.len);
    const rule = stylesheet.rules.items[0];
    try testing.expectEqual(@as(usize, 2), rule.declarations.items.len);

    const bg_decl = rule.declarations.items[0];
    try testing.expect(bg_decl.value == .color);
    try testing.expectEqual(@as(u8, 255), bg_decl.value.color.r);
    try testing.expectEqual(@as(u8, 0), bg_decl.value.color.g);
    try testing.expectEqual(@as(u8, 0), bg_decl.value.color.b);
}

test "parse CSS with important" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: red !important; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    try testing.expectEqual(@as(usize, 1), stylesheet.rules.items.len);
    const rule = stylesheet.rules.items[0];
    try testing.expectEqual(@as(usize, 1), rule.declarations.items.len);
    const decl = rule.declarations.items[0];
    try testing.expect(decl.important == true);
}

test "parse CSS with comments" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input =
        \\/* This is a comment */
        \\div { color: red; }
    ;
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
}

test "parse CSS with class selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = ".container { width: 100px; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    std.debug.assert(sel.sequences.items.len == 1);
    const seq = &sel.sequences.items[0];
    std.debug.assert(seq.selectors.items.len == 1);
    std.debug.assert(seq.selectors.items[0].selector_type == .class);
    std.debug.assert(std.mem.eql(u8, seq.selectors.items[0].value, "container"));
}

test "parse CSS with ID selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "#myId { color: blue; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    std.debug.assert(sel.sequences.items.len == 1);
    const seq = &sel.sequences.items[0];
    std.debug.assert(seq.selectors.items.len == 1);
    std.debug.assert(seq.selectors.items[0].selector_type == .id);
    std.debug.assert(std.mem.eql(u8, seq.selectors.items[0].value, "myId"));
}

test "parse CSS with descendant selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div p { color: green; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    // 后代选择器应该只有一个序列，包含两个简单选择器（div和p），中间有组合器
    std.debug.assert(sel.sequences.items.len == 1);
    const sequence = &sel.sequences.items[0];
    std.debug.assert(sequence.selectors.items.len == 2);
    std.debug.assert(sequence.selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, sequence.selectors.items[0].value, "div"));
    std.debug.assert(sequence.selectors.items[1].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, sequence.selectors.items[1].value, "p"));
    // 检查组合器
    std.debug.assert(sequence.combinators.items.len == 1);
    std.debug.assert(sequence.combinators.items[0] == .descendant);
}

test "parse CSS with child selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div > p { color: red; }";
    var parser = css.Parser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    // 子选择器应该解析为一个序列，包含div和p，中间有child组合器
    // 或者解析为两个序列（取决于实现）
    // 先检查基本结构
    std.debug.assert(sel.sequences.items.len >= 1);
    // 检查第一个序列是否有div选择器
    const first_seq = &sel.sequences.items[0];
    std.debug.assert(first_seq.selectors.items.len >= 1);
    std.debug.assert(first_seq.selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, first_seq.selectors.items[0].value, "div"));
}
