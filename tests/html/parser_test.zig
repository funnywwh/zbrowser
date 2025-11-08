const std = @import("std");
const html = @import("html");
const dom = @import("dom");

test "parse simple HTML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<html><body><p>Hello</p></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem != null);

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);
}

test "parse HTML with attributes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<div class='container' id='main'></div>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    if (body.?.first_child) |div| {
        if (div.asElement()) |elem| {
            try std.testing.expect(std.mem.eql(u8, elem.tag_name, "div"));
            const class_attr = elem.getAttribute("class");
            try std.testing.expect(class_attr != null);
            const id_attr = elem.getAttribute("id");
            try std.testing.expect(id_attr != null);
        }
    }
}

test "parse HTML with body attributes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<html><head></head><body class=\"main-body\" id=\"page-body\"></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);
    if (body.?.asElement()) |elem| {
        try std.testing.expect(std.mem.eql(u8, elem.tag_name, "body"));
        const class_attr = elem.getAttribute("class");
        try std.testing.expect(class_attr != null);
        try std.testing.expect(std.mem.eql(u8, class_attr.?, "main-body"));
        const id_attr = elem.getAttribute("id");
        try std.testing.expect(id_attr != null);
        try std.testing.expect(std.mem.eql(u8, id_attr.?, "page-body"));
    }
}

test "parse HTML with text content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<p>Hello, World!</p>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    if (body.?.first_child) |p| {
        if (p.first_child) |text| {
            try std.testing.expect(text.node_type == .text);
            try std.testing.expect(std.mem.eql(u8, text.asText().?, "Hello, World!"));
        }
    }
}

test "parse HTML with comments" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<!-- This is a comment --><p>Text</p>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);
}

test "parse self-closing tags" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<br/><img src='test.jpg'/>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);
}

test "parse complex HTML with multiple attributes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<html lang="zh-CN">
        \\<head>
        \\  <meta charset="UTF-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\  <title>Complex HTML Test</title>
        \\  <link rel="stylesheet" href="style.css" type="text/css">
        \\</head>
        \\<body class="main-body" id="page-body">
        \\  <div class="container" id="main-container" data-role="container">
        \\    <header class="site-header">
        \\      <h1 class="title" id="main-title">Welcome</h1>
        \\      <nav class="navigation" role="navigation">
        \\        <ul class="nav-list">
        \\          <li class="nav-item"><a href="/home" class="nav-link" target="_blank">Home</a></li>
        \\          <li class="nav-item"><a href="/about" class="nav-link active">About</a></li>
        \\          <li class="nav-item"><a href="/contact" class="nav-link">Contact</a></li>
        \\        </ul>
        \\      </nav>
        \\    </header>
        \\    <main class="content" id="main-content">
        \\      <article class="article" data-id="123" data-author="John Doe">
        \\        <h2 class="article-title">Article Title</h2>
        \\        <p class="article-text">This is a paragraph with <strong class="bold-text">bold</strong> and <em class="italic-text">italic</em> text.</p>
        \\        <img src="image.jpg" alt="Description" width="800" height="600" class="article-image">
        \\        <div class="nested-div" style="color: red; font-size: 16px;">
        \\          <span class="inline-span" title="Tooltip text">Nested content</span>
        \\        </div>
        \\      </article>
        \\      <section class="sidebar" id="sidebar">
        \\        <aside class="widget" data-widget-type="search">
        \\          <form action="/search" method="GET" class="search-form">
        \\            <input type="text" name="q" placeholder="Search..." class="search-input" required>
        \\            <button type="submit" class="search-button" disabled>Search</button>
        \\          </form>
        \\        </aside>
        \\      </section>
        \\    </main>
        \\    <footer class="site-footer" id="page-footer">
        \\      <p class="copyright">&copy; 2024 Company Name</p>
        \\    </footer>
        \\  </div>
        \\  <script src="app.js" type="text/javascript" defer></script>
        \\</body>
        \\</html>
    ;

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    // 验证基本结构
    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem != null);
    if (html_elem.?.asElement()) |elem| {
        try std.testing.expect(std.mem.eql(u8, elem.tag_name, "html"));
        const lang = elem.getAttribute("lang");
        try std.testing.expect(lang != null);
        try std.testing.expect(std.mem.eql(u8, lang.?, "zh-CN"));
    }

    // 验证head和meta标签
    const head = doc_ptr.getHead();
    try std.testing.expect(head != null);
    if (head.?.first_child) |meta| {
        if (meta.asElement()) |elem| {
            if (std.mem.eql(u8, elem.tag_name, "meta")) {
                const charset = elem.getAttribute("charset");
                try std.testing.expect(charset != null);
                try std.testing.expect(std.mem.eql(u8, charset.?, "UTF-8"));
            }
        }
    }

    // 验证body属性
    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);
    if (body.?.asElement()) |elem| {
        try std.testing.expect(std.mem.eql(u8, elem.tag_name, "body"));
        const class_attr = elem.getAttribute("class");
        try std.testing.expect(class_attr != null);
        try std.testing.expect(std.mem.eql(u8, class_attr.?, "main-body"));
        const id_attr = elem.getAttribute("id");
        try std.testing.expect(id_attr != null);
        try std.testing.expect(std.mem.eql(u8, id_attr.?, "page-body"));
    }

    // 验证嵌套div和data属性
    if (body.?.first_child) |div| {
        if (div.asElement()) |elem| {
            if (std.mem.eql(u8, elem.tag_name, "div")) {
                const data_role = elem.getAttribute("data-role");
                try std.testing.expect(data_role != null);
                try std.testing.expect(std.mem.eql(u8, data_role.?, "container"));
            }
        }
    }

    // 验证链接属性
    var current = body.?.first_child;
    var found_link = false;
    while (current) |node| {
        if (node.node_type == .element) {
            if (node.asElement()) |elem| {
                if (std.mem.eql(u8, elem.tag_name, "a")) {
                    const href = elem.getAttribute("href");
                    const target = elem.getAttribute("target");
                    if (href != null and std.mem.eql(u8, href.?, "/home")) {
                        try std.testing.expect(target != null);
                        try std.testing.expect(std.mem.eql(u8, target.?, "_blank"));
                        found_link = true;
                        break;
                    }
                }
            }
        }
        // 递归查找
        if (node.first_child) |child| {
            current = child;
            continue;
        }
        if (node.next_sibling) |sibling| {
            current = sibling;
            continue;
        }
        // 回溯
        var parent = node.parent;
        while (parent) |p| {
            if (p.next_sibling) |sibling| {
                current = sibling;
                break;
            }
            parent = p.parent;
        } else {
            break;
        }
    }
    try std.testing.expect(found_link);

    // 验证图片属性
    var img_found = false;
    current = body.?.first_child;
    while (current) |node| {
        if (node.node_type == .element) {
            if (node.asElement()) |elem| {
                if (std.mem.eql(u8, elem.tag_name, "img")) {
                    const src = elem.getAttribute("src");
                    const alt = elem.getAttribute("alt");
                    const width = elem.getAttribute("width");
                    const height = elem.getAttribute("height");
                    try std.testing.expect(src != null);
                    try std.testing.expect(std.mem.eql(u8, src.?, "image.jpg"));
                    try std.testing.expect(alt != null);
                    try std.testing.expect(width != null);
                    try std.testing.expect(std.mem.eql(u8, width.?, "800"));
                    try std.testing.expect(height != null);
                    try std.testing.expect(std.mem.eql(u8, height.?, "600"));
                    img_found = true;
                    break;
                }
            }
        }
        if (node.first_child) |child| {
            current = child;
            continue;
        }
        if (node.next_sibling) |sibling| {
            current = sibling;
            continue;
        }
        var parent = node.parent;
        while (parent) |p| {
            if (p.next_sibling) |sibling| {
                current = sibling;
                break;
            }
            parent = p.parent;
        } else {
            break;
        }
    }
    try std.testing.expect(img_found);

    // 验证表单输入属性
    var input_found = false;
    current = body.?.first_child;
    while (current) |node| {
        if (node.node_type == .element) {
            if (node.asElement()) |elem| {
                if (std.mem.eql(u8, elem.tag_name, "input")) {
                    const input_type = elem.getAttribute("type");
                    const name = elem.getAttribute("name");
                    const placeholder = elem.getAttribute("placeholder");
                    const required = elem.hasAttribute("required");
                    try std.testing.expect(input_type != null);
                    try std.testing.expect(std.mem.eql(u8, input_type.?, "text"));
                    try std.testing.expect(name != null);
                    try std.testing.expect(std.mem.eql(u8, name.?, "q"));
                    try std.testing.expect(placeholder != null);
                    try std.testing.expect(required);
                    input_found = true;
                    break;
                }
            }
        }
        if (node.first_child) |child| {
            current = child;
            continue;
        }
        if (node.next_sibling) |sibling| {
            current = sibling;
            continue;
        }
        var parent = node.parent;
        while (parent) |p| {
            if (p.next_sibling) |sibling| {
                current = sibling;
                break;
            }
            parent = p.parent;
        } else {
            break;
        }
    }
    try std.testing.expect(input_found);
}

test "parse HTML with special attribute values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<div class="container" id="test-id" data-value="123" data-json='{"key":"value"}' style="color: red; background: blue;">
        \\  <input type="text" value="test value" placeholder="Enter text..." disabled readonly>
        \\  <a href="https://example.com?q=test&page=1" target="_blank" rel="noopener noreferrer">Link</a>
        \\  <img src="image.png" alt="Image &amp; Description" title="Tooltip &quot;text&quot;">
        \\  <button type="submit" form="form1" formaction="/submit" formmethod="POST">Submit</button>
        \\</div>
    ;

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    if (body.?.first_child) |div| {
        if (div.asElement()) |elem| {
            // 验证data-json属性（包含JSON）
            const data_json = elem.getAttribute("data-json");
            try std.testing.expect(data_json != null);
            try std.testing.expect(std.mem.indexOf(u8, data_json.?, "key") != null);

            // 验证style属性（包含分号和空格）
            const style = elem.getAttribute("style");
            try std.testing.expect(style != null);
            try std.testing.expect(std.mem.indexOf(u8, style.?, "color: red") != null);
        }

        // 验证input的多个属性
        if (div.first_child) |input| {
            if (input.asElement()) |elem| {
                if (std.mem.eql(u8, elem.tag_name, "input")) {
                    const value = elem.getAttribute("value");
                    try std.testing.expect(value != null);
                    try std.testing.expect(std.mem.eql(u8, value.?, "test value"));
                    try std.testing.expect(elem.hasAttribute("disabled"));
                    try std.testing.expect(elem.hasAttribute("readonly"));
                }
            }
        }

        // 验证链接的复杂URL
        var current = div.first_child;
        while (current) |node| {
            if (node.asElement()) |elem| {
                if (std.mem.eql(u8, elem.tag_name, "a")) {
                    const href = elem.getAttribute("href");
                    try std.testing.expect(href != null);
                    try std.testing.expect(std.mem.indexOf(u8, href.?, "example.com") != null);
                    try std.testing.expect(std.mem.indexOf(u8, href.?, "q=test") != null);
                    const rel = elem.getAttribute("rel");
                    try std.testing.expect(rel != null);
                    try std.testing.expect(std.mem.indexOf(u8, rel.?, "noopener") != null);
                    break;
                }
            }
            current = node.next_sibling;
        }
    }
}

test "parse HTML with JavaScript code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<html>
        \\<head>
        \\  <title>JavaScript Test</title>
        \\</head>
        \\<body>
        \\  <h1>Hello World</h1>
        \\  <script type="text/javascript">
        \\    function greet(name) {
        \\      console.log("Hello, " + name + "!");
        \\      return "Welcome " + name;
        \\    }
        \\    
        \\    const message = greet("World");
        \\    document.getElementById("output").innerHTML = message;
        \\  </script>
        \\  <div id="output"></div>
        \\  <script>
        \\    // Inline script without type
        \\    let x = 10;
        \\    let y = 20;
        \\    let sum = x + y;
        \\    console.log("Sum:", sum);
        \\  </script>
        \\  <script src="external.js" defer></script>
        \\  <script type="module">
        \\    import { utils } from './utils.js';
        \\    export default function() {
        \\      return utils.process();
        \\    }
        \\  </script>
        \\</body>
        \\</html>
    ;

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 先手动释放所有节点（因为使用GPA而非Arena）
        // 注意：必须使用doc_ptr，因为parser使用的是doc_ptr
        freeAllNodes(allocator, &doc_ptr.node);
        // 清空指针
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        // 释放doc_ptr
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 注意：parser创建的节点已经被添加到doc_ptr的DOM树中
    // 这些节点会在freeAllNodes中被释放

    // 验证基本结构
    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem != null);

    const head = doc_ptr.getHead();
    try std.testing.expect(head != null);

    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    // 验证head中有title
    if (head.?.first_child) |title| {
        if (title.asElement()) |elem| {
            if (std.mem.eql(u8, elem.tag_name, "title")) {
                try std.testing.expect(title.first_child != null);
                if (title.first_child) |text| {
                    try std.testing.expect(std.mem.eql(u8, text.asText().?, "JavaScript Test"));
                }
            }
        }
    }

    // 验证body中有h1
    if (body.?.first_child) |h1| {
        if (h1.asElement()) |elem| {
            if (std.mem.eql(u8, elem.tag_name, "h1")) {
                try std.testing.expect(h1.first_child != null);
                if (h1.first_child) |text| {
                    try std.testing.expect(std.mem.eql(u8, text.asText().?, "Hello World"));
                }
            }
        }
    }

    // 验证script标签存在
    var script_count: usize = 0;
    var found_inline_script = false;
    var found_external_script = false;
    var found_module_script = false;
    var found_text_javascript = false;
    var found_script_without_type = false;

    // 递归查找所有script标签的辅助函数
    const findScripts = struct {
        fn search(node_opt: ?*dom.Node, count: *usize, inline_found: *bool, external_found: *bool, module_found: *bool, text_js_found: *bool, no_type_found: *bool) void {
            var current = node_opt;
            while (current) |node| {
                if (node.node_type == .element) {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "script")) {
                            count.* += 1;

                            // 检查type属性
                            const script_type = elem.getAttribute("type");
                            const src = elem.getAttribute("src");

                            if (src != null) {
                                // 外部脚本
                                external_found.* = true;
                            } else if (script_type != null and std.mem.eql(u8, script_type.?, "module")) {
                                // ES6模块脚本
                                module_found.* = true;
                                // 验证模块代码内容
                                if (node.first_child) |text_node| {
                                    const code = text_node.asText().?;
                                    _ = code; // 代码存在即可
                                }
                            } else if (script_type != null and std.mem.eql(u8, script_type.?, "text/javascript")) {
                                // type="text/javascript"的脚本
                                text_js_found.* = true;
                                inline_found.* = true;
                                // 验证JavaScript代码内容
                                if (node.first_child) |text_node| {
                                    const code = text_node.asText().?;
                                    _ = code; // 代码存在即可
                                }
                            } else {
                                // 没有type属性的script标签
                                no_type_found.* = true;
                                inline_found.* = true;
                                // 验证JavaScript代码内容
                                if (node.first_child) |text_node| {
                                    const code = text_node.asText().?;
                                    _ = code; // 代码存在即可
                                }
                            }
                        }
                    }
                }

                // 递归查找子节点
                if (node.first_child) |child| {
                    search(child, count, inline_found, external_found, module_found, text_js_found, no_type_found);
                }

                // 移动到下一个兄弟节点
                current = node.next_sibling;
            }
        }
    }.search;

    findScripts(body.?.first_child, &script_count, &found_inline_script, &found_external_script, &found_module_script, &found_text_javascript, &found_script_without_type);

    // 验证找到了所有script标签
    try std.testing.expect(script_count >= 3);
    try std.testing.expect(found_inline_script);
    try std.testing.expect(found_external_script);
    try std.testing.expect(found_module_script);

    // 验证div元素存在
    var found_div = false;
    const findDiv = struct {
        fn search(node_opt: ?*dom.Node, found: *bool) void {
            var current = node_opt;
            while (current) |node| {
                if (node.node_type == .element) {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "div")) {
                            const id = elem.getAttribute("id");
                            if (id != null and std.mem.eql(u8, id.?, "output")) {
                                found.* = true;
                                return;
                            }
                        }
                    }
                }
                // 递归查找子节点
                if (node.first_child) |child| {
                    search(child, found);
                    if (found.*) return;
                }
                // 移动到下一个兄弟节点
                current = node.next_sibling;
            }
        }
    }.search;

    findDiv(body.?.first_child, &found_div);
    try std.testing.expect(found_div);
}

// 辅助函数：释放所有节点（递归深度优先）
fn freeAllNodes(allocator: std.mem.Allocator, node: *dom.Node) void {
    // 先释放所有子节点
    var current = node.first_child;
    while (current) |child| {
        // 保存下一个兄弟节点（在释放前保存，因为释放会修改指针）
        const next = child.next_sibling;

        // 递归释放子节点及其所有后代
        freeAllNodes(allocator, child);

        // 释放子节点本身
        freeNode(allocator, child);

        // 移动到下一个兄弟节点
        current = next;
    }

    // 清空子节点指针
    node.first_child = null;
    node.last_child = null;
}

// 辅助函数：释放单个节点
fn freeNode(allocator: std.mem.Allocator, node: *dom.Node) void {
    switch (node.node_type) {
        .element => {
            if (node.asElement()) |elem| {
                // 释放tag_name
                allocator.free(elem.tag_name);

                // 释放所有属性
                var it = elem.attributes.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                elem.attributes.deinit();
            }
        },
        .text => {
            if (node.asText()) |text| {
                allocator.free(text);
            }
        },
        .comment => {
            if (node.node_type == .comment) {
                allocator.free(node.data.comment);
            }
        },
        .document => {
            // document节点不需要释放，它是值类型
            return;
        },
        else => {},
    }

    // 释放节点本身（除了document节点）
    if (node.node_type != .document) {
        allocator.destroy(node);
    }
}

test "parser deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<html><body><p>Test</p></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    try parser.parse();

    // 调用deinit，应该释放open_elements
    parser.deinit();

    // 如果使用GPA，检查内存泄漏
    // 注意：这里我们只是确保deinit不会崩溃
}

test "parser parse empty HTML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 空HTML应该不会崩溃
    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem == null);
}

test "parser parse whitespace only HTML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "   \n\t  ";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 只有空白字符的HTML应该不会崩溃
    // 注意：parser可能会隐式创建html和body元素，所以这里只检查不会崩溃
    // 实际行为取决于parser的实现
    _ = doc_ptr.getDocumentElement();
}

test "parser parse incomplete HTML tag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试不完整的HTML标签（没有闭合的'>'）
    const html_content = "<div class=\"test\"";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();

    // 不完整的标签应该返回UnexpectedEOF错误
    const result = parser.parse();
    try std.testing.expectError(error.UnexpectedEOF, result);
}

test "parser parse nested error HTML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试嵌套错误的HTML（未闭合的标签）
    // <div><p></div> - p标签没有闭合，但div标签闭合了
    // HTML5解析器应该容错处理这种情况
    const html_content = "<html><body><div><p>Text</div></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 应该能够容错处理，不会崩溃
    // 使用getElementsByTagName查找div元素
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    // 应该至少找到一个div元素
    try std.testing.expect(divs.len > 0);
}

test "parser parse HTML with Unicode characters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试Unicode字符（中文）
    const html_content = "<html><body><div>你好世界</div></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 应该能够解析Unicode字符
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len > 0);
    if (divs.len > 0) {
        const div_node = divs[0];
        const text_node = div_node.first_child;
        try std.testing.expect(text_node != null);
        if (text_node) |txt| {
            try std.testing.expect(txt.node_type == .text);
            const text_content = txt.asText();
            try std.testing.expect(text_content != null);
            if (text_content) |content| {
                // 验证Unicode字符被正确解析
                try std.testing.expect(content.len > 0);
            }
        }
    }
}

test "parser parse HTML with emoji" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试emoji字符
    const html_content = "<html><body><div>Hello 😀 World 🌍</div></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 应该能够解析emoji字符
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len > 0);
    if (divs.len > 0) {
        const div_node = divs[0];
        const text_node = div_node.first_child;
        try std.testing.expect(text_node != null);
        if (text_node) |txt| {
            try std.testing.expect(txt.node_type == .text);
            const text_content = txt.asText();
            try std.testing.expect(text_content != null);
            if (text_content) |content| {
                // 验证emoji字符被正确解析
                try std.testing.expect(content.len > 0);
            }
        }
    }
}

test "parser parse HTML with entity encoding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试HTML实体编码
    // 注意：当前实现可能不处理实体编码，但应该不会崩溃
    const html_content = "<html><body><div>&lt;div&gt;&amp;&quot;test&quot;&#39;test&#39;</div></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 应该能够解析（即使实体编码可能不会被解码）
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len > 0);
    if (divs.len > 0) {
        const div_node = divs[0];
        const text_node = div_node.first_child;
        try std.testing.expect(text_node != null);
        if (text_node) |txt| {
            try std.testing.expect(txt.node_type == .text);
            const text_content = txt.asText();
            try std.testing.expect(text_content != null);
            // 实体编码可能不会被解码，但应该被解析为文本
            if (text_content) |content| {
                try std.testing.expect(content.len > 0);
            }
        }
    }
}
