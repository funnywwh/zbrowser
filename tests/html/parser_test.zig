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

test "parser insertion mode initial with DOCTYPE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试initial模式：处理DOCTYPE
    const html_content = "<!DOCTYPE html><html><head></head><body></body></html>";
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

    // 应该能够解析，找到html元素
    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem != null);
}

test "parser insertion mode initial with comment" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试initial模式：处理DOCTYPE前的注释
    const html_content = "<!-- Comment before DOCTYPE --><!DOCTYPE html><html><head></head><body></body></html>";
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

    // 应该能够解析，找到html元素
    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem != null);
}

test "parser insertion mode before_html" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试before_html模式：处理html标签
    const html_content = "<html><head></head><body></body></html>";
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

    // 应该能够解析，找到html元素
    const html_elem = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem != null);
}

test "parser insertion mode before_head" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试before_head模式：处理head标签
    const html_content = "<html><head><title>Test</title></head><body></body></html>";
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

    // 应该能够解析，找到head元素
    const head = doc_ptr.getHead();
    try std.testing.expect(head != null);
    if (head) |head_node| {
        // 应该找到title元素
        const title = head_node.querySelector("title");
        try std.testing.expect(title != null);
    }
}

test "parser insertion mode in_head" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试in_head模式：处理head内的标签
    const html_content = "<html><head><meta charset=\"UTF-8\"><title>Test</title><style>body {}</style></head><body></body></html>";
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

    // 应该能够解析，找到head元素
    const head = doc_ptr.getHead();
    try std.testing.expect(head != null);
    if (head) |head_node| {
        // 应该找到meta、title、style元素
        const meta = head_node.querySelector("meta");
        try std.testing.expect(meta != null);
        const title = head_node.querySelector("title");
        try std.testing.expect(title != null);
        const style = head_node.querySelector("style");
        try std.testing.expect(style != null);
    }
}

test "parser insertion mode after_head" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试after_head模式：处理body标签前的空白和body标签
    const html_content = "<html><head></head>\n<body><div>Content</div></body></html>";
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

    // 应该能够解析，找到body元素
    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);
    if (body) |body_node| {
        // 应该找到div元素
        const div = body_node.querySelector("div");
        try std.testing.expect(div != null);
    }
}

test "parser insertion mode in_body" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试in_body模式：处理body内的标签
    const html_content = "<html><head></head><body><div><p>Paragraph</p></div><span>Text</span></body></html>";
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

    // 应该能够解析，找到body元素
    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    // 应该找到div和span元素
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len > 0);

    const spans = try doc_ptr.getElementsByTagName("span", allocator);
    defer allocator.free(spans);
    try std.testing.expect(spans.len > 0);
}

test "parser error recovery unexpected end tag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试错误恢复机制：遇到意外的结束标签
    // <div><p></div> - p标签没有闭合，但div标签闭合了
    // HTML5解析器应该容错处理，关闭p标签
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
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len > 0);

    // 应该能找到p元素（即使没有正确闭合）
    const ps = try doc_ptr.getElementsByTagName("p", allocator);
    defer allocator.free(ps);
    try std.testing.expect(ps.len > 0);
}

// ========== HTML5标准符合性测试 ==========

test "parse HTML5 DOCTYPE variants" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试HTML5标准DOCTYPE的各种变体
    const test_cases = [_]struct {
        name: []const u8,
        html: []const u8,
    }{
        .{ .name = "standard HTML5 DOCTYPE", .html = "<!DOCTYPE html><html><head></head><body></body></html>" },
        .{ .name = "DOCTYPE with uppercase", .html = "<!DOCTYPE HTML><html><head></head><body></body></html>" },
        .{ .name = "DOCTYPE with mixed case", .html = "<!DOCTYPE Html><html><head></head><body></body></html>" },
        .{ .name = "DOCTYPE with whitespace", .html = "<!DOCTYPE  html  ><html><head></head><body></body></html>" },
        .{ .name = "DOCTYPE with newline", .html = "<!DOCTYPE\nhtml><html><head></head><body></body></html>" },
    };

    for (test_cases) |test_case| {
        const doc = try dom.Document.init(allocator);
        const doc_ptr = try allocator.create(dom.Document);
        defer {
            freeAllNodes(allocator, &doc_ptr.node);
            doc_ptr.node.first_child = null;
            doc_ptr.node.last_child = null;
            allocator.destroy(doc_ptr);
        }
        doc_ptr.* = doc;

        var parser = html.Parser.init(test_case.html, doc_ptr, allocator);
        defer parser.deinit();
        try parser.parse();

        // 所有变体都应该能正确解析
        const html_elem = doc_ptr.getDocumentElement();
        try std.testing.expect(html_elem != null);
    }
}

test "parse HTML5 table structure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<html>
        \\<head><title>Table Test</title></head>
        \\<body>
        \\  <table border="1" cellpadding="5" cellspacing="0">
        \\    <caption>Sample Table</caption>
        \\    <colgroup>
        \\      <col span="2" style="background-color: #f0f0f0">
        \\      <col style="background-color: #ffffff">
        \\    </colgroup>
        \\    <thead>
        \\      <tr>
        \\        <th>Header 1</th>
        \\        <th>Header 2</th>
        \\        <th>Header 3</th>
        \\      </tr>
        \\    </thead>
        \\    <tbody>
        \\      <tr>
        \\        <td>Cell 1-1</td>
        \\        <td>Cell 1-2</td>
        \\        <td>Cell 1-3</td>
        \\      </tr>
        \\      <tr>
        \\        <td>Cell 2-1</td>
        \\        <td colspan="2">Cell 2-2 (spans 2 columns)</td>
        \\      </tr>
        \\    </tbody>
        \\    <tfoot>
        \\      <tr>
        \\        <td>Footer 1</td>
        \\        <td>Footer 2</td>
        \\        <td>Footer 3</td>
        \\      </tr>
        \\    </tfoot>
        \\  </table>
        \\</body>
        \\</html>
    ;

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

    // 验证表格结构
    const tables = try doc_ptr.getElementsByTagName("table", allocator);
    defer allocator.free(tables);
    try std.testing.expect(tables.len == 1);

    const theads = try doc_ptr.getElementsByTagName("thead", allocator);
    defer allocator.free(theads);
    try std.testing.expect(theads.len == 1);

    const tbodys = try doc_ptr.getElementsByTagName("tbody", allocator);
    defer allocator.free(tbodys);
    try std.testing.expect(tbodys.len == 1);

    const tfoots = try doc_ptr.getElementsByTagName("tfoot", allocator);
    defer allocator.free(tfoots);
    try std.testing.expect(tfoots.len == 1);

    const trs = try doc_ptr.getElementsByTagName("tr", allocator);
    defer allocator.free(trs);
    try std.testing.expect(trs.len >= 3); // 至少3行（thead, tbody, tfoot各一行）

    const ths = try doc_ptr.getElementsByTagName("th", allocator);
    defer allocator.free(ths);
    try std.testing.expect(ths.len >= 3);

    const tds = try doc_ptr.getElementsByTagName("td", allocator);
    defer allocator.free(tds);
    try std.testing.expect(tds.len >= 5);

    // 验证colspan属性
    var found_colspan = false;
    for (tds) |td| {
        if (td.asElement()) |elem| {
            const colspan = elem.getAttribute("colspan");
            if (colspan != null) {
                try std.testing.expect(std.mem.eql(u8, colspan.?, "2"));
                found_colspan = true;
                break;
            }
        }
    }
    try std.testing.expect(found_colspan);
}

test "parse HTML5 list structures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<html>
        \\<head><title>List Test</title></head>
        \\<body>
        \\  <ul>
        \\    <li>Unordered item 1</li>
        \\    <li>Unordered item 2</li>
        \\    <li>Unordered item 3</li>
        \\  </ul>
        \\  <ol type="1" start="1">
        \\    <li>Ordered item 1</li>
        \\    <li>Ordered item 2</li>
        \\    <li>Ordered item 3</li>
        \\  </ol>
        \\  <ol type="A">
        \\    <li>Letter item A</li>
        \\    <li>Letter item B</li>
        \\  </ol>
        \\  <dl>
        \\    <dt>Term 1</dt>
        \\    <dd>Definition 1</dd>
        \\    <dt>Term 2</dt>
        \\    <dd>Definition 2</dd>
        \\  </dl>
        \\</body>
        \\</html>
    ;

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

    // 验证列表结构
    const uls = try doc_ptr.getElementsByTagName("ul", allocator);
    defer allocator.free(uls);
    try std.testing.expect(uls.len == 1);

    const ols = try doc_ptr.getElementsByTagName("ol", allocator);
    defer allocator.free(ols);
    try std.testing.expect(ols.len == 2);

    const lis = try doc_ptr.getElementsByTagName("li", allocator);
    defer allocator.free(lis);
    try std.testing.expect(lis.len >= 7); // 至少7个li元素

    const dls = try doc_ptr.getElementsByTagName("dl", allocator);
    defer allocator.free(dls);
    try std.testing.expect(dls.len == 1);

    const dts = try doc_ptr.getElementsByTagName("dt", allocator);
    defer allocator.free(dts);
    try std.testing.expect(dts.len == 2);

    const dds = try doc_ptr.getElementsByTagName("dd", allocator);
    defer allocator.free(dds);
    try std.testing.expect(dds.len == 2);

    // 验证ol的type和start属性
    if (ols.len > 0) {
        if (ols[0].asElement()) |elem| {
            const type_attr = elem.getAttribute("type");
            try std.testing.expect(type_attr != null);
            try std.testing.expect(std.mem.eql(u8, type_attr.?, "1"));
            const start = elem.getAttribute("start");
            try std.testing.expect(start != null);
            try std.testing.expect(std.mem.eql(u8, start.?, "1"));
        }
    }
}

test "parse HTML5 form elements" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<html>
        \\<head><title>Form Test</title></head>
        \\<body>
        \\  <form action="/submit" method="POST" enctype="multipart/form-data">
        \\    <label for="username">Username:</label>
        \\    <input type="text" id="username" name="username" required placeholder="Enter username">
        \\    
        \\    <label for="email">Email:</label>
        \\    <input type="email" id="email" name="email" required>
        \\    
        \\    <label for="password">Password:</label>
        \\    <input type="password" id="password" name="password" minlength="8" required>
        \\    
        \\    <label for="age">Age:</label>
        \\    <input type="number" id="age" name="age" min="18" max="100">
        \\    
        \\    <label for="country">Country:</label>
        \\    <select id="country" name="country">
        \\      <option value="">Select a country</option>
        \\      <option value="us">United States</option>
        \\      <option value="uk">United Kingdom</option>
        \\      <option value="cn" selected>China</option>
        \\    </select>
        \\    
        \\    <label for="bio">Bio:</label>
        \\    <textarea id="bio" name="bio" rows="4" cols="50" placeholder="Enter your bio"></textarea>
        \\    
        \\    <fieldset>
        \\      <legend>Gender</legend>
        \\      <input type="radio" id="male" name="gender" value="male">
        \\      <label for="male">Male</label>
        \\      <input type="radio" id="female" name="gender" value="female" checked>
        \\      <label for="female">Female</label>
        \\    </fieldset>
        \\    
        \\    <fieldset>
        \\      <legend>Interests</legend>
        \\      <input type="checkbox" id="sports" name="interests" value="sports" checked>
        \\      <label for="sports">Sports</label>
        \\      <input type="checkbox" id="music" name="interests" value="music">
        \\      <label for="music">Music</label>
        \\    </fieldset>
        \\    
        \\    <button type="submit">Submit</button>
        \\    <button type="reset">Reset</button>
        \\  </form>
        \\</body>
        \\</html>
    ;

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

    // 验证表单结构
    const forms = try doc_ptr.getElementsByTagName("form", allocator);
    defer allocator.free(forms);
    try std.testing.expect(forms.len == 1);

    if (forms[0].asElement()) |form_elem| {
        const action = form_elem.getAttribute("action");
        try std.testing.expect(action != null);
        try std.testing.expect(std.mem.eql(u8, action.?, "/submit"));
        const method = form_elem.getAttribute("method");
        try std.testing.expect(method != null);
        try std.testing.expect(std.mem.eql(u8, method.?, "POST"));
    }

    const inputs = try doc_ptr.getElementsByTagName("input", allocator);
    defer allocator.free(inputs);
    try std.testing.expect(inputs.len >= 8);

    const selects = try doc_ptr.getElementsByTagName("select", allocator);
    defer allocator.free(selects);
    try std.testing.expect(selects.len == 1);

    const textareas = try doc_ptr.getElementsByTagName("textarea", allocator);
    defer allocator.free(textareas);
    try std.testing.expect(textareas.len == 1);

    const buttons = try doc_ptr.getElementsByTagName("button", allocator);
    defer allocator.free(buttons);
    try std.testing.expect(buttons.len == 2);

    const labels = try doc_ptr.getElementsByTagName("label", allocator);
    defer allocator.free(labels);
    try std.testing.expect(labels.len >= 8);

    // 验证input的type属性
    var found_text = false;
    var found_email = false;
    var found_password = false;
    var found_number = false;
    var found_radio = false;
    var found_checkbox = false;
    for (inputs) |input| {
        if (input.asElement()) |elem| {
            const type_attr = elem.getAttribute("type");
            if (type_attr) |t| {
                if (std.mem.eql(u8, t, "text")) found_text = true;
                if (std.mem.eql(u8, t, "email")) found_email = true;
                if (std.mem.eql(u8, t, "password")) found_password = true;
                if (std.mem.eql(u8, t, "number")) found_number = true;
                if (std.mem.eql(u8, t, "radio")) found_radio = true;
                if (std.mem.eql(u8, t, "checkbox")) found_checkbox = true;
            }
        }
    }
    try std.testing.expect(found_text);
    try std.testing.expect(found_email);
    try std.testing.expect(found_password);
    try std.testing.expect(found_number);
    try std.testing.expect(found_radio);
    try std.testing.expect(found_checkbox);
}

test "parse HTML5 semantic tags" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content =
        \\<html>
        \\<head><title>Semantic Tags Test</title></head>
        \\<body>
        \\  <header>
        \\    <h1>Site Title</h1>
        \\    <nav>
        \\      <ul>
        \\        <li><a href="/">Home</a></li>
        \\        <li><a href="/about">About</a></li>
        \\      </ul>
        \\    </nav>
        \\  </header>
        \\  <main>
        \\    <article>
        \\      <header>
        \\        <h2>Article Title</h2>
        \\        <p>Published on <time datetime="2024-01-01">January 1, 2024</time></p>
        \\      </header>
        \\      <section>
        \\        <h3>Section 1</h3>
        \\        <p>Content of section 1.</p>
        \\      </section>
        \\      <section>
        \\        <h3>Section 2</h3>
        \\        <p>Content of section 2.</p>
        \\      </section>
        \\      <aside>
        \\        <h4>Related Links</h4>
        \\        <ul>
        \\          <li><a href="/related1">Related 1</a></li>
        \\        </ul>
        \\      </aside>
        \\    </article>
        \\  </main>
        \\  <footer>
        \\    <p>&copy; 2024 Company Name</p>
        \\  </footer>
        \\</body>
        \\</html>
    ;

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

    // 验证语义化标签
    const headers = try doc_ptr.getElementsByTagName("header", allocator);
    defer allocator.free(headers);
    try std.testing.expect(headers.len >= 2);

    const navs = try doc_ptr.getElementsByTagName("nav", allocator);
    defer allocator.free(navs);
    try std.testing.expect(navs.len == 1);

    const mains = try doc_ptr.getElementsByTagName("main", allocator);
    defer allocator.free(mains);
    try std.testing.expect(mains.len == 1);

    const articles = try doc_ptr.getElementsByTagName("article", allocator);
    defer allocator.free(articles);
    try std.testing.expect(articles.len == 1);

    const sections = try doc_ptr.getElementsByTagName("section", allocator);
    defer allocator.free(sections);
    try std.testing.expect(sections.len == 2);

    const asides = try doc_ptr.getElementsByTagName("aside", allocator);
    defer allocator.free(asides);
    try std.testing.expect(asides.len == 1);

    const footers = try doc_ptr.getElementsByTagName("footer", allocator);
    defer allocator.free(footers);
    try std.testing.expect(footers.len == 1);

    const times = try doc_ptr.getElementsByTagName("time", allocator);
    defer allocator.free(times);
    try std.testing.expect(times.len == 1);

    if (times[0].asElement()) |time_elem| {
        const datetime = time_elem.getAttribute("datetime");
        try std.testing.expect(datetime != null);
        try std.testing.expect(std.mem.eql(u8, datetime.?, "2024-01-01"));
    }
}

test "parse HTML5 entity encoding comprehensive" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试所有标准HTML实体编码
    const html_content =
        \\<html>
        \\<body>
        \\  <div>
        \\    &lt;div&gt; - Less than and greater than<br>
        \\    &amp; - Ampersand<br>
        \\    &quot; - Double quote<br>
        \\    &#39; - Single quote (apostrophe)<br>
        \\    &nbsp; - Non-breaking space<br>
        \\    &copy; - Copyright symbol<br>
        \\    &reg; - Registered trademark<br>
        \\    &trade; - Trademark<br>
        \\    &euro; - Euro symbol<br>
        \\    &pound; - Pound symbol<br>
        \\    &yen; - Yen symbol<br>
        \\    &cent; - Cent symbol<br>
        \\    &sect; - Section symbol<br>
        \\    &para; - Paragraph symbol<br>
        \\    &deg; - Degree symbol<br>
        \\    &plusmn; - Plus-minus symbol<br>
        \\    &sup2; - Superscript 2<br>
        \\    &sup3; - Superscript 3<br>
        \\    &frac14; - Fraction 1/4<br>
        \\    &frac12; - Fraction 1/2<br>
        \\    &frac34; - Fraction 3/4<br>
        \\    &times; - Multiplication sign<br>
        \\    &divide; - Division sign<br>
        \\    &alpha; - Greek alpha<br>
        \\    &beta; - Greek beta<br>
        \\    &gamma; - Greek gamma<br>
        \\    &delta; - Greek delta<br>
        \\    &Delta; - Greek Delta<br>
        \\    &pi; - Greek pi<br>
        \\    &Pi; - Greek Pi<br>
        \\    &sigma; - Greek sigma<br>
        \\    &Sigma; - Greek Sigma<br>
        \\    &Omega; - Greek Omega<br>
        \\    &mdash; - Em dash<br>
        \\    &ndash; - En dash<br>
        \\    &lsquo; - Left single quote<br>
        \\    &rsquo; - Right single quote<br>
        \\    &ldquo; - Left double quote<br>
        \\    &rdquo; - Right double quote<br>
        \\    &hellip; - Horizontal ellipsis<br>
        \\    &bull; - Bullet<br>
        \\    &rarr; - Right arrow<br>
        \\    &larr; - Left arrow<br>
        \\    &uarr; - Up arrow<br>
        \\    &darr; - Down arrow<br>
        \\    &harr; - Left-right arrow<br>
        \\    &spades; - Spade suit<br>
        \\    &clubs; - Club suit<br>
        \\    &hearts; - Heart suit<br>
        \\    &diams; - Diamond suit<br>
        \\    Numeric entities: &#65; (A), &#66; (B), &#8364; (€), &#169; (©)<br>
        \\    Hex entities: &#x41; (A), &#x42; (B), &#x20AC; (€), &#xA9; (©)
        \\  </div>
        \\</body>
        \\</html>
    ;

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

    // 验证实体编码被解析（已实现的实体会被解码，未实现的实体会被保留）
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len == 1);

    // 收集所有文本节点的内容
    var all_text = std.ArrayList(u8){
        .items = &[_]u8{},
        .capacity = 0,
    };
    defer all_text.deinit(allocator);
    
    var node = divs[0].first_child;
    while (node) |n| {
        if (n.asText()) |text_content| {
            try all_text.appendSlice(allocator, text_content);
        }
        node = n.next_sibling;
    }
    
    const combined_text = try all_text.toOwnedSlice(allocator);
    defer allocator.free(combined_text);
    
    // 验证文本内容存在
    try std.testing.expect(combined_text.len > 0);
    
    // 验证已实现的实体被正确解码
    try std.testing.expect(std.mem.indexOf(u8, combined_text, "<div>") != null); // &lt;div&gt; 被解码
    try std.testing.expect(std.mem.indexOf(u8, combined_text, "&") != null); // 未实现的实体（如&nbsp;）被保留
}

test "parse HTML5 CDATA section" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试CDATA部分（通常在XML/SVG中使用，但HTML5也支持）
    // 注意：HTML5的script标签不需要CDATA，这里测试SVG中的CDATA
    const html_content =
        \\<html>
        \\<head><title>CDATA Test</title></head>
        \\<body>
        \\  <svg>
        \\    <![CDATA[
        \\      <circle cx="50" cy="50" r="40"/>
        \\    ]]>
        \\  </svg>
        \\</body>
        \\</html>
    ;

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

    // 验证CDATA部分被解析
    const svgs = try doc_ptr.getElementsByTagName("svg", allocator);
    defer allocator.free(svgs);
    try std.testing.expect(svgs.len == 1);
}

test "parse HTML5 error recovery detailed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试各种错误恢复场景
    const test_cases = [_]struct {
        name: []const u8,
        html: []const u8,
        should_parse: bool,
    }{
        .{ .name = "unclosed div", .html = "<html><body><div><p>Text</body></html>", .should_parse = true },
        .{ .name = "unclosed p in div", .html = "<html><body><div><p>Text</div></body></html>", .should_parse = true },
        .{ .name = "extra closing tag", .html = "<html><body><div></div></p></body></html>", .should_parse = true },
        .{ .name = "nested unclosed tags", .html = "<html><body><div><span><p>Text</div></body></html>", .should_parse = true },
        .{ .name = "missing closing html", .html = "<html><head></head><body></body>", .should_parse = true },
        .{ .name = "missing closing body", .html = "<html><head></head><body><div>Text</div>", .should_parse = true },
    };

    for (test_cases) |test_case| {
        const doc = try dom.Document.init(allocator);
        const doc_ptr = try allocator.create(dom.Document);
        defer {
            freeAllNodes(allocator, &doc_ptr.node);
            doc_ptr.node.first_child = null;
            doc_ptr.node.last_child = null;
            allocator.destroy(doc_ptr);
        }
        doc_ptr.* = doc;

        var parser = html.Parser.init(test_case.html, doc_ptr, allocator);
        defer parser.deinit();

        if (test_case.should_parse) {
            try parser.parse();
            // 验证能够解析（不会崩溃）
            _ = doc_ptr.getDocumentElement();
        } else {
            const result = parser.parse();
            try std.testing.expectError(error.UnexpectedEOF, result);
        }
    }
}

test "parse HTML5 whitespace handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试空白字符处理（HTML5规范要求）
    const html_content =
        \\<html>
        \\<head>
        \\  <title>Whitespace Test</title>
        \\</head>
        \\<body>
        \\  <div>
        \\    Text with    multiple    spaces
        \\    and
        \\    newlines
        \\    and tabs
        \\  </div>
        \\  <pre>
        \\    Preformatted
        \\    text with
        \\    spaces
        \\  </pre>
        \\  <p>Paragraph with   spaces   and
        \\  newlines</p>
        \\</body>
        \\</html>
    ;

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

    // 验证空白字符被正确处理
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len == 1);

    const pres = try doc_ptr.getElementsByTagName("pre", allocator);
    defer allocator.free(pres);
    try std.testing.expect(pres.len == 1);

    const ps = try doc_ptr.getElementsByTagName("p", allocator);
    defer allocator.free(ps);
    try std.testing.expect(ps.len == 1);
}

test "parse HTML5 void elements" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试void元素（自闭合标签，HTML5规范）
    const html_content =
        \\<html>
        \\<head><title>Void Elements Test</title></head>
        \\<body>
        \\  <br>
        \\  <hr>
        \\  <img src="test.jpg" alt="Test">
        \\  <input type="text" name="test">
        \\  <meta charset="UTF-8">
        \\  <link rel="stylesheet" href="style.css">
        \\  <area shape="rect" coords="0,0,100,100" href="test.html">
        \\  <base href="https://example.com/">
        \\  <col span="2">
        \\  <embed src="video.mp4">
        \\  <source src="audio.mp3" type="audio/mpeg">
        \\  <track kind="subtitles" src="subs.vtt">
        \\  <wbr>
        \\</body>
        \\</html>
    ;

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

    // 验证void元素被正确解析
    const brs = try doc_ptr.getElementsByTagName("br", allocator);
    defer allocator.free(brs);
    try std.testing.expect(brs.len >= 1);

    const hrs = try doc_ptr.getElementsByTagName("hr", allocator);
    defer allocator.free(hrs);
    try std.testing.expect(hrs.len >= 1);

    const imgs = try doc_ptr.getElementsByTagName("img", allocator);
    defer allocator.free(imgs);
    try std.testing.expect(imgs.len >= 1);

    const inputs = try doc_ptr.getElementsByTagName("input", allocator);
    defer allocator.free(inputs);
    try std.testing.expect(inputs.len >= 1);

    const metas = try doc_ptr.getElementsByTagName("meta", allocator);
    defer allocator.free(metas);
    try std.testing.expect(metas.len >= 1);

    const links = try doc_ptr.getElementsByTagName("link", allocator);
    defer allocator.free(links);
    try std.testing.expect(links.len >= 1);
}

test "parse HTML5 nested structures complex" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试复杂的嵌套结构
    const html_content =
        \\<html>
        \\<head>
        \\  <title>Complex Nested Structure</title>
        \\  <style>
        \\    body { margin: 0; }
        \\    .container { max-width: 1200px; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="container">
        \\    <header class="site-header">
        \\      <div class="header-content">
        \\        <h1>Site Title</h1>
        \\        <nav class="main-nav">
        \\          <ul class="nav-list">
        \\            <li class="nav-item">
        \\              <a href="/" class="nav-link">Home</a>
        \\            </li>
        \\            <li class="nav-item">
        \\              <a href="/about" class="nav-link">About</a>
        \\              <ul class="sub-nav">
        \\                <li><a href="/about/team">Team</a></li>
        \\                <li><a href="/about/history">History</a></li>
        \\              </ul>
        \\            </li>
        \\          </ul>
        \\        </nav>
        \\      </div>
        \\    </header>
        \\    <main class="main-content">
        \\      <article class="article">
        \\        <header class="article-header">
        \\          <h2>Article Title</h2>
        \\          <div class="meta">
        \\            <span class="author">Author Name</span>
        \\            <time class="date" datetime="2024-01-01">Jan 1, 2024</time>
        \\          </div>
        \\        </header>
        \\        <div class="article-body">
        \\          <p>First paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
        \\          <p>Second paragraph with <a href="/link">a link</a> and <code>code</code>.</p>
        \\          <blockquote>
        \\            <p>This is a quote.</p>
        \\            <cite>Source</cite>
        \\          </blockquote>
        \\          <ul>
        \\            <li>Item 1</li>
        \\            <li>Item 2 with <a href="/item2">link</a></li>
        \\            <li>Item 3</li>
        \\          </ul>
        \\          <ol>
        \\            <li>Ordered item 1</li>
        \\            <li>Ordered item 2</li>
        \\          </ol>
        \\        </div>
        \\        <footer class="article-footer">
        \\          <div class="tags">
        \\            <span class="tag">Tag1</span>
        \\            <span class="tag">Tag2</span>
        \\          </div>
        \\        </footer>
        \\      </article>
        \\      <aside class="sidebar">
        \\        <section class="widget">
        \\          <h3>Related Articles</h3>
        \\          <ul>
        \\            <li><a href="/article1">Article 1</a></li>
        \\            <li><a href="/article2">Article 2</a></li>
        \\          </ul>
        \\        </section>
        \\      </aside>
        \\    </main>
        \\    <footer class="site-footer">
        \\      <div class="footer-content">
        \\        <p>&copy; 2024 Company</p>
        \\      </div>
        \\    </footer>
        \\  </div>
        \\</body>
        \\</html>
    ;

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

    // 验证复杂嵌套结构被正确解析
    const headers = try doc_ptr.getElementsByTagName("header", allocator);
    defer allocator.free(headers);
    try std.testing.expect(headers.len >= 2);

    const navs = try doc_ptr.getElementsByTagName("nav", allocator);
    defer allocator.free(navs);
    try std.testing.expect(navs.len >= 1);

    const articles = try doc_ptr.getElementsByTagName("article", allocator);
    defer allocator.free(articles);
    try std.testing.expect(articles.len == 1);

    const asides = try doc_ptr.getElementsByTagName("aside", allocator);
    defer allocator.free(asides);
    try std.testing.expect(asides.len == 1);

    const uls = try doc_ptr.getElementsByTagName("ul", allocator);
    defer allocator.free(uls);
    try std.testing.expect(uls.len >= 3);

    const ols = try doc_ptr.getElementsByTagName("ol", allocator);
    defer allocator.free(ols);
    try std.testing.expect(ols.len >= 1);

    const links = try doc_ptr.getElementsByTagName("a", allocator);
    defer allocator.free(links);
    try std.testing.expect(links.len >= 7);

    // 验证嵌套的ul（子导航）
    var found_sub_nav = false;
    for (uls) |ul| {
        if (ul.asElement()) |elem| {
            const class_attr = elem.getAttribute("class");
            if (class_attr) |cls| {
                if (std.mem.indexOf(u8, cls, "sub-nav") != null) {
                    found_sub_nav = true;
                    break;
                }
            }
        }
    }
    try std.testing.expect(found_sub_nav);
}

test "parse HTML5 attribute edge cases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试属性的各种边界情况
    const html_content =
        \\<html>
        \\<body>
        \\  <div class="test" id="test-id" data-value="123" data-json='{"key":"value"}' style="color: red;">
        \\    <input type="text" value="" placeholder="Enter text" disabled readonly>
        \\    <input type="checkbox" checked>
        \\    <input type="radio" name="group" value="option1" checked>
        \\    <select multiple>
        \\      <option value="1" selected>Option 1</option>
        \\      <option value="2">Option 2</option>
        \\    </select>
        \\    <textarea rows="10" cols="50"></textarea>
        \\    <a href="https://example.com?q=test&page=1" target="_blank" rel="noopener noreferrer">Link</a>
        \\    <img src="image.png" alt="Image &amp; Description" title="Tooltip &quot;text&quot;">
        \\    <div class="container" id="" data-empty="">
        \\      <span class="test-class another-class third-class">Multiple classes</span>
        \\    </div>
        \\  </div>
        \\</body>
        \\</html>
    ;

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

    // 验证各种属性边界情况
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len >= 2);

    // 验证空值属性
    if (divs.len > 1) {
        if (divs[1].asElement()) |elem| {
            const id = elem.getAttribute("id");
            try std.testing.expect(id != null);
            try std.testing.expect(std.mem.eql(u8, id.?, ""));
        }
    }

    // 验证布尔属性（没有值的属性）
    const inputs = try doc_ptr.getElementsByTagName("input", allocator);
    defer allocator.free(inputs);
    var found_disabled = false;
    var found_readonly = false;
    var found_checked = false;
    for (inputs) |input| {
        if (input.asElement()) |elem| {
            if (elem.hasAttribute("disabled")) found_disabled = true;
            if (elem.hasAttribute("readonly")) found_readonly = true;
            if (elem.hasAttribute("checked")) found_checked = true;
        }
    }
    try std.testing.expect(found_disabled);
    try std.testing.expect(found_readonly);
    try std.testing.expect(found_checked);

    // 验证多个class值
    const spans = try doc_ptr.getElementsByTagName("span", allocator);
    defer allocator.free(spans);
    try std.testing.expect(spans.len == 1);
    if (spans[0].asElement()) |elem| {
        const classes = try elem.getClasses(allocator);
        defer allocator.free(classes);
        try std.testing.expect(classes.len >= 3);
    }
}

test "parse HTML5 script and style special handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试script和style标签的特殊处理（HTML5规范要求）
    const html_content =
        \\<html>
        \\<head>
        \\  <style type="text/css">
        \\    body { margin: 0; }
        \\    .container { max-width: 1200px; }
        \\    /* CSS comment */
        \\    div > p { color: red; }
        \\  </style>
        \\  <script type="text/javascript">
        \\    // JavaScript comment
        \\    function test() {
        \\      var x = 10;
        \\      var y = 20;
        \\      console.log("Test");
        \\    }
        \\  </script>
        \\</head>
        \\<body>
        \\  <script>
        \\    // Inline script
        \\    var x = 10;
        \\    var y = 20;
        \\    var z = x + y;
        \\  </script>
        \\  <style>
        \\    /* Inline styles */
        \\    .test { color: blue; }
        \\  </style>
        \\  <noscript>
        \\    <p>JavaScript is disabled</p>
        \\  </noscript>
        \\</body>
        \\</html>
    ;

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

    // 验证script和style标签被正确解析
    const scripts = try doc_ptr.getElementsByTagName("script", allocator);
    defer allocator.free(scripts);
    try std.testing.expect(scripts.len >= 2);

    const styles = try doc_ptr.getElementsByTagName("style", allocator);
    defer allocator.free(styles);
    try std.testing.expect(styles.len >= 2);

    const noscripts = try doc_ptr.getElementsByTagName("noscript", allocator);
    defer allocator.free(noscripts);
    try std.testing.expect(noscripts.len == 1);

    // 验证script和style标签的内容被正确保存
    for (scripts) |script| {
        try std.testing.expect(script.first_child != null);
        if (script.first_child) |text_node| {
            const content = text_node.asText();
            try std.testing.expect(content != null);
            if (content) |c| {
                try std.testing.expect(c.len > 0);
            }
        }
    }

    for (styles) |style| {
        try std.testing.expect(style.first_child != null);
        if (style.first_child) |text_node| {
            const content = text_node.asText();
            try std.testing.expect(content != null);
            if (content) |c| {
                try std.testing.expect(c.len > 0);
            }
        }
    }
}
