const std = @import("std");
const css = @import("css");

test "parse simple CSS rule" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: red; }";
    var parser = css.Parser.init(css_input, allocator);
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
    const rule = stylesheet.rules.items[0];
    std.debug.assert(rule.selectors.items.len == 1);
    std.debug.assert(std.mem.eql(u8, rule.selectors.items[0], "div"));
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
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 2);

    const rule1 = stylesheet.rules.items[0];
    std.debug.assert(std.mem.eql(u8, rule1.selectors.items[0], "div"));
    std.debug.assert(rule1.declarations.items[0].name.len > 0);

    const rule2 = stylesheet.rules.items[1];
    std.debug.assert(std.mem.eql(u8, rule2.selectors.items[0], "p"));
}

test "parse CSS with length values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { width: 100px; height: 50%; }";
    var parser = css.Parser.init(css_input, allocator);
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
    var stylesheet = try parser.parse();
    defer stylesheet.deinit();

    std.debug.assert(stylesheet.rules.items.len == 1);
}
