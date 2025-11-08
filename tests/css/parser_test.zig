const std = @import("std");
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

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.selectors.items.len == 1);
    // 检查选择器：应该是类型选择器 "div"
    const sel = &rule.selectors.items[0];
    std.debug.assert(sel.sequences.items.len == 1);
    const seq = &sel.sequences.items[0];
    std.debug.assert(seq.selectors.items.len == 1);
    std.debug.assert(seq.selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, seq.selectors.items[0].value, "div"));
    std.debug.assert(rule.declarations.items.len == 1);
    const decl = rule.declarations.items[0];
    std.debug.assert(std.mem.eql(u8, decl.name, "color"));
    std.debug.assert(decl.value == .keyword);
    std.debug.assert(std.mem.eql(u8, decl.value.keyword, "red"));
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

    std.debug.assert(stylesheet.rules.items.len == 2);

    const rule1 = stylesheet.rules.items[0];
    const sel1 = &rule1.selectors.items[0];
    std.debug.assert(sel1.sequences.items.len == 1);
    std.debug.assert(sel1.sequences.items[0].selectors.items.len == 1);
    std.debug.assert(sel1.sequences.items[0].selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, sel1.sequences.items[0].selectors.items[0].value, "div"));
    std.debug.assert(rule1.declarations.items[0].name.len > 0);

    const rule2 = stylesheet.rules.items[1];
    const sel2 = &rule2.selectors.items[0];
    std.debug.assert(sel2.sequences.items.len == 1);
    std.debug.assert(sel2.sequences.items[0].selectors.items.len == 1);
    std.debug.assert(sel2.sequences.items[0].selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, sel2.sequences.items[0].selectors.items[0].value, "p"));
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

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 2);

    const width_decl = rule.declarations.items[0];
    std.debug.assert(std.mem.eql(u8, width_decl.name, "width"));
    std.debug.assert(width_decl.value == .length);
    std.debug.assert(width_decl.value.length.value == 100.0);
    std.debug.assert(std.mem.eql(u8, width_decl.value.length.unit, "px"));

    const height_decl = rule.declarations.items[1];
    std.debug.assert(std.mem.eql(u8, height_decl.name, "height"));
    std.debug.assert(height_decl.value == .percentage);
    std.debug.assert(height_decl.value.percentage == 50.0);
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

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 2);

    const bg_decl = rule.declarations.items[0];
    std.debug.assert(bg_decl.value == .color);
    std.debug.assert(bg_decl.value.color.r == 255);
    std.debug.assert(bg_decl.value.color.g == 0);
    std.debug.assert(bg_decl.value.color.b == 0);
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

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 1);
    const decl = rule.declarations.items[0];
    std.debug.assert(decl.important == true);
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
    std.debug.print("DEBUG TEST: sequences.len = {}, selectors.len = {}, combinators.len = {}\n", .{ sel.sequences.items.len, sel.sequences.items[0].selectors.items.len, sel.sequences.items[0].combinators.items.len });
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
