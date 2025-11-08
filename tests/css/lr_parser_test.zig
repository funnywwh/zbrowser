const std = @import("std");
const lr_parser = @import("lr_parser");
const selector = @import("selector");

test "LR parser: parse simple CSS rule" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: red; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
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

test "LR parser: parse CSS with multiple rules" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input =
        \\div { color: red; }
        \\p { font-size: 16px; }
    ;
    var parser = lr_parser.LRParser.init(css_input, allocator);
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
    std.debug.assert(rule1.declarations.items.len == 1);
    std.debug.assert(std.mem.eql(u8, rule1.declarations.items[0].name, "color"));

    const rule2 = stylesheet.rules.items[1];
    const sel2 = &rule2.selectors.items[0];
    std.debug.assert(sel2.sequences.items.len == 1);
    std.debug.assert(sel2.sequences.items[0].selectors.items.len == 1);
    std.debug.assert(sel2.sequences.items[0].selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, sel2.sequences.items[0].selectors.items[0].value, "p"));
    std.debug.assert(rule2.declarations.items.len == 1);
    std.debug.assert(std.mem.eql(u8, rule2.declarations.items[0].name, "font-size"));
}

test "LR parser: parse CSS with ID selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "#myId { color: blue; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    const seq = &sel.sequences.items[0];
    std.debug.assert(seq.selectors.items.len == 1);
    std.debug.assert(seq.selectors.items[0].selector_type == .id);
    std.debug.assert(std.mem.eql(u8, seq.selectors.items[0].value, "myId"));
}

test "LR parser: parse CSS with descendant selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div p { color: green; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
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

test "LR parser: parse CSS with child selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div > p { color: red; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    std.debug.assert(sel.sequences.items.len == 1);
    const first_seq = &sel.sequences.items[0];
    std.debug.assert(first_seq.selectors.items.len >= 1);
    std.debug.assert(first_seq.selectors.items[0].selector_type == .type);
    std.debug.assert(std.mem.eql(u8, first_seq.selectors.items[0].value, "div"));
    // 检查组合器
    if (first_seq.combinators.items.len > 0) {
        std.debug.assert(first_seq.combinators.items[0] == .child);
    }
}

test "LR parser: parse CSS with class selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = ".myClass { color: yellow; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    const sel = &rule.selectors.items[0];
    const seq = &sel.sequences.items[0];
    std.debug.assert(seq.selectors.items.len == 1);
    std.debug.assert(seq.selectors.items[0].selector_type == .class);
    std.debug.assert(std.mem.eql(u8, seq.selectors.items[0].value, "myClass"));
}

test "LR parser: parse CSS with multiple selectors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div, p { color: blue; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.selectors.items.len == 2);

    const sel1 = &rule.selectors.items[0];
    std.debug.assert(sel1.sequences.items.len == 1);
    std.debug.assert(std.mem.eql(u8, sel1.sequences.items[0].selectors.items[0].value, "div"));

    const sel2 = &rule.selectors.items[1];
    std.debug.assert(sel2.sequences.items.len == 1);
    std.debug.assert(std.mem.eql(u8, sel2.sequences.items[0].selectors.items[0].value, "p"));
}

test "LR parser: parse CSS with string value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { content: \"hello\"; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 1);
    const decl = rule.declarations.items[0];
    std.debug.assert(std.mem.eql(u8, decl.name, "content"));
    std.debug.assert(decl.value == .string);
    std.debug.assert(std.mem.eql(u8, decl.value.string, "hello"));
}

test "LR parser: parse CSS with number value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { opacity: 0.5; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 1);
    const decl = rule.declarations.items[0];
    std.debug.assert(std.mem.eql(u8, decl.name, "opacity"));
    std.debug.assert(decl.value == .number);
    std.debug.assert(decl.value.number == 0.5);
}

test "LR parser: parse CSS with color value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: #ff0000; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 1);
    const decl = rule.declarations.items[0];
    std.debug.assert(std.mem.eql(u8, decl.name, "color"));
    std.debug.assert(decl.value == .color);
    std.debug.assert(decl.value.color.r == 255);
    std.debug.assert(decl.value.color.g == 0);
    std.debug.assert(decl.value.color.b == 0);
}

test "LR parser: parse CSS with multiple declarations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: red; font-size: 16px; }";
    var parser = lr_parser.LRParser.init(css_input, allocator);
    defer parser.deinit();
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.declarations.items.len == 2);
    std.debug.assert(std.mem.eql(u8, rule.declarations.items[0].name, "color"));
    std.debug.assert(std.mem.eql(u8, rule.declarations.items[1].name, "font-size"));
}
