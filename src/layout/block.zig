const std = @import("std");
const builtin = @import("builtin");
const box = @import("box");
const style_utils = @import("style_utils");
const parser = @import("parser");

/// 调试输出函数（只在Debug模式下输出）
/// 使用条件编译，在Release模式下完全移除，避免性能影响
inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}

/// 计算块级元素宽度
/// 简化实现：如果已经设置了宽度，使用设置的宽度；否则使用containing_block的宽度
pub fn calculateBlockWidth(layout_box: *box.LayoutBox, containing_block: box.Size) f32 {
    // 如果已经设置了宽度（且不是通过auto计算得到的），使用设置的宽度
    // 注意：如果content.width > 0，可能是之前计算的结果，需要检查是否是CSS设置的width
    // 简化实现：如果content.width > 0，且不等于containing_block.width，说明是CSS设置的width
    if (layout_box.box_model.content.width > 0 and layout_box.box_model.content.width != containing_block.width) {
        return layout_box.box_model.content.width;
    }

    // 否则使用containing_block的宽度（auto宽度）
    return containing_block.width;
}

/// 块级布局算法
/// 根据CSS规范实现块级格式化上下文的布局
pub fn layoutBlock(layout_box: *box.LayoutBox, containing_block: box.Size) !void {
    // 调试日志：记录元素信息
    const tag_name = if (layout_box.node.node_type == .element)
        if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown"
    else
        "text";

    // 1. 计算宽度（考虑margin、padding和border）
    // 统一计算逻辑：确保padding/border只减一次，避免重复计算
    //
    // CSS规范说明：
    // - width属性指的是content width（在content-box模式下）
    // - containing_block.width可能是视口宽度（根元素）或父元素的content width（非根元素）
    // - 无论哪种情况，计算逻辑应该一致：content width = available_width - padding - border
    //   其中 available_width = containing_block.width - margin.left - margin.right
    //
    // 关键点：containing_block.width在传递给子元素时，已经是父元素的content.width
    // （在layoutBlock的子元素循环中，child_containing_block.width = layout_box.box_model.content.width）
    // 所以不需要区分containing_block的类型，统一计算即可

    // 计算可用宽度（减去margin）
    const available_width = containing_block.width - layout_box.box_model.margin.left - layout_box.box_model.margin.right;

    // 计算块级元素宽度（可能是auto或CSS设置的width）
    const width = calculateBlockWidth(layout_box, box.Size{ .width = available_width, .height = containing_block.height });

    // 如果content width还未计算，进行计算
    if (layout_box.box_model.content.width == 0) {
        if (width == available_width) {
            // auto宽度：需要减去padding和border得到content width
            // 统一计算：无论containing_block是什么类型，都减去padding和border
            const padding_horizontal = layout_box.box_model.padding.left + layout_box.box_model.padding.right;
            const border_horizontal = layout_box.box_model.border.left + layout_box.box_model.border.right;
            layout_box.box_model.content.width = available_width - padding_horizontal - border_horizontal;
        } else {
            // 设置了width：width已经是content width（在style_utils中已经根据box-sizing处理过）
            layout_box.box_model.content.width = width;
        }
    }
    // 如果content width已经设置，使用已设置的值（避免重复计算）

    // 调试：记录h1元素的width计算
    if (std.mem.eql(u8, tag_name, "h1")) {
        debugPrint("[WIDTH DEBUG] h1: containing_block.width={d:.1}, available_width={d:.1}, calculated_width={d:.1}\n", .{
            containing_block.width,
            available_width,
            width,
        });
    }
    const is_root = layout_box.parent == null;

    if (is_root or std.mem.eql(u8, tag_name, "body") or std.mem.eql(u8, tag_name, "html")) {
        debugPrint("[LAYOUT] Element: {s}, is_root: {}\n", .{ tag_name, is_root });
        debugPrint("  margin: top={d:.1}, right={d:.1}, bottom={d:.1}, left={d:.1}\n", .{
            layout_box.box_model.margin.top,
            layout_box.box_model.margin.right,
            layout_box.box_model.margin.bottom,
            layout_box.box_model.margin.left,
        });
        debugPrint("  padding: top={d:.1}, right={d:.1}, bottom={d:.1}, left={d:.1}\n", .{
            layout_box.box_model.padding.top,
            layout_box.box_model.padding.right,
            layout_box.box_model.padding.bottom,
            layout_box.box_model.padding.left,
        });
        debugPrint("  content: x={d:.1}, y={d:.1}, width={d:.1}, height={d:.1}\n", .{
            layout_box.box_model.content.x,
            layout_box.box_model.content.y,
            layout_box.box_model.content.width,
            layout_box.box_model.content.height,
        });
        debugPrint("  containing_block: width={d:.1}, height={d:.1}\n", .{ containing_block.width, containing_block.height });
    }

    // 2. 应用margin到位置（如果父元素存在）
    // 在块级布局中，元素的margin应该影响元素相对于父元素的位置
    // 如果父元素存在，当前元素的位置 = 父元素内容区域位置 + 父元素padding + 当前元素margin
    // 但是，由于布局是递归的，当前元素的位置应该在父元素的block.zig中计算
    // 这里只处理根元素的位置
    if (layout_box.parent == null) {
        // 根元素（html）的内容区域从(0, 0)开始
        // 根元素的margin会影响根元素的总尺寸，但不影响内容区域的位置
        // 这是CSS规范的要求：根元素的内容区域始终从(0, 0)开始
        layout_box.box_model.content.x = 0;
        layout_box.box_model.content.y = 0;
        if (std.mem.eql(u8, tag_name, "html")) {
            debugPrint("[LAYOUT] Root element (html) position set to (0, 0)\n", .{});
        }
    } else if (std.mem.eql(u8, tag_name, "body")) {
        // body元素的位置计算：
        // - body的content.x = html.content.x + body.margin.left = 0 + body.margin.left
        // - body的content.y = html.content.y + body.margin.top = 0 + body.margin.top
        // 注意：body的padding不影响body自身的位置，只影响body子元素的位置
        // 如果html.content.y不是0，说明有问题，应该修复
        if (layout_box.parent.?.box_model.content.x != 0 or layout_box.parent.?.box_model.content.y != 0) {
            debugPrint("[LAYOUT WARNING] html.content is not (0, 0): x={d:.1}, y={d:.1}\n", .{
                layout_box.parent.?.box_model.content.x,
                layout_box.parent.?.box_model.content.y,
            });
        }
        // body的位置应该在父元素（html）的layoutBlock中计算，但这里验证一下
        // 如果body.content.x/y还未设置，使用默认值（应该在父元素中设置）
        if (layout_box.box_model.content.x == 0 and layout_box.box_model.content.y == 0) {
            // body的content位置 = html.content + body.margin
            // 由于html.content = (0, 0)，所以body.content = body.margin
            layout_box.box_model.content.x = layout_box.box_model.margin.left;
            layout_box.box_model.content.y = layout_box.box_model.margin.top;
            debugPrint("[LAYOUT] Body element position set: x={d:.1}, y={d:.1} (margin: left={d:.1}, top={d:.1})\n", .{
                layout_box.box_model.content.x,
                layout_box.box_model.content.y,
                layout_box.box_model.margin.left,
                layout_box.box_model.margin.top,
            });
        }
    }

    // 3. 计算子元素布局
    // 注意：这里y从padding.top开始，因为子元素的位置是相对于父元素的内容区域的
    // 但是，如果父元素没有padding/border，第一子元素的margin-top会与父元素的margin-top折叠
    var y: f32 = layout_box.box_model.padding.top;

    // 检查父元素是否有padding或border（这会阻止margin折叠）
    const has_parent_padding_or_border = (layout_box.box_model.padding.top > 0 or
        layout_box.box_model.padding.bottom > 0 or
        layout_box.box_model.border.top > 0 or
        layout_box.box_model.border.bottom > 0);

    // 标记是否是第一个子元素（用于margin折叠判断）
    var is_first_visible_child = true;

    // 遍历所有子元素
    for (layout_box.children.items) |child| {
        // 跳过head、title、meta、script、style、link等元数据标签（它们不应该参与布局）
        var should_skip = false;
        if (child.node.node_type == .element) {
            if (child.node.asElement()) |elem| {
                const child_elem_tag = elem.tag_name;
                if (std.mem.eql(u8, child_elem_tag, "title") or
                    std.mem.eql(u8, child_elem_tag, "head") or
                    std.mem.eql(u8, child_elem_tag, "meta") or
                    std.mem.eql(u8, child_elem_tag, "script") or
                    std.mem.eql(u8, child_elem_tag, "style") or
                    std.mem.eql(u8, child_elem_tag, "link"))
                {
                    should_skip = true;
                }
            }
        }

        // 跳过空白文本节点（它们不应该参与布局）
        if (!should_skip and child.node.node_type == .text) {
            const text_content = child.node.data.text;
            var is_whitespace = true;
            for (text_content) |char| {
                if (!std.ascii.isWhitespace(char)) {
                    is_whitespace = false;
                    break;
                }
            }
            if (is_whitespace) {
                should_skip = true;
            }
        }

        // 如果应该跳过，继续下一个子元素
        if (should_skip) {
            continue;
        }

        // 处理浮动元素
        if (child.float != .none) {
            // 关键修复：浮动元素需要先计算自己的宽度和高度
            // 1. 先计算浮动元素的宽度（使用containing_block的宽度作为参考）
            const child_containing_block = box.Size{
                .width = width - layout_box.box_model.padding.left - layout_box.box_model.padding.right,
                .height = containing_block.height,
            };

            // 2. 计算浮动元素的宽度（如果CSS中设置了width，会在这里设置）
            const child_width = calculateBlockWidth(child, child_containing_block);
            child.box_model.content.width = child_width;

            // 3. 布局浮动元素的子元素（递归调用）
            try layoutBlock(child, child_containing_block);

            // 4. 调用浮动布局函数
            // 注意：浮动元素应该相对于包含块的content区域
            // layout_box（containing_block）的content.y应该已经在父元素的layoutBlock中设置
            // 如果还没有设置，说明layout_box是根元素，content.y应该是0
            // 但是，如果layout_box是body的子元素，它的content.y应该在body布局时设置
            // 由于浮动元素在layout_box的layoutBlock中被处理，此时layout_box的content.y可能还没有被设置
            // 所以，我们需要使用layout_box的当前content.y（如果还没有设置，应该是0或之前的值）
            const float_module = @import("float");
            float_module.layoutFloat(child, layout_box, &y);
            continue;
        }

        // 跳过absolute和fixed定位的元素（它们不参与正常流布局）
        if (child.position == .absolute or child.position == .fixed) {
            continue;
        }

        // 布局子元素（递归调用，暂时简化处理）
        // TODO: 根据子元素的display类型选择不同的布局算法
        // 先布局子元素，无论是否有子元素
        // 注意：layout_box.box_model.content.width已经是content width（已经减去了padding）
        // containing_block的width应该是父元素的content width（已经减去了padding）
        const parent_tag_name = if (layout_box.node.node_type == .element)
            if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown"
        else
            "text";
        const child_tag_name = if (child.node.node_type == .element)
            if (child.node.asElement()) |elem| elem.tag_name else "unknown"
        else
            "text";

        // 调试：记录body的子元素containing_block计算
        if (std.mem.eql(u8, parent_tag_name, "body") and std.mem.eql(u8, child_tag_name, "h1")) {
            debugPrint("[CONTAINING BLOCK] body.content.width={d:.1}, child_containing_block.width={d:.1}\n", .{
                layout_box.box_model.content.width,
                layout_box.box_model.content.width,
            });
        }
        const child_containing_block = box.Size{
            .width = layout_box.box_model.content.width, // 使用content width（已经减去了padding）
            .height = containing_block.height,
        };
        try layoutBlock(child, child_containing_block);

        // 计算子元素位置（考虑margin和padding）
        // 子元素的位置 = 父元素内容区域位置 + 父元素padding + 子元素margin
        // 注意：父元素的margin应该影响父元素的位置，而不是子元素的位置
        // 所以，子元素的位置是相对于父元素的内容区域的，不需要考虑父元素的margin

        const old_x = child.box_model.content.x;
        const old_y = child.box_model.content.y;
        // 注意：如果 child.content.x 已经被设置过（非0），说明已经计算过了，不要重复计算
        // 这可以避免在多次布局调用时重复计算位置
        if (child.box_model.content.x == 0) {
            child.box_model.content.x = layout_box.box_model.content.x + layout_box.box_model.padding.left + child.box_model.margin.left;
        }
        // y 坐标需要每次都更新，因为它是累积的
        // 使用局部y变量（每个block formatting context独立）
        //
        // Margin折叠规则（CSS规范）：
        // - 如果父元素有padding或border，子元素的margin-top不会与父元素的margin-top折叠
        // - 第一子元素的margin-top应该与父元素的margin-top折叠（如果父元素没有padding/border）
        // - 折叠时取两者中的较大值
        //
        // 注意：margin折叠影响的是父元素和子元素之间的间距
        // 如果发生折叠，子元素的位置 = 父元素content.y + 折叠后的margin
        // 如果不发生折叠，子元素的位置 = 父元素content.y + padding.top + 子元素margin.top
        var child_y_offset: f32 = undefined;
        if (is_first_visible_child and !has_parent_padding_or_border) {
            // Margin折叠：第一子元素的margin-top与父元素的margin-top折叠
            // 取两者中的较大值
            const collapsed_margin = @max(layout_box.box_model.margin.top, child.box_model.margin.top);
            // 子元素位置 = 父元素content.y + 折叠后的margin
            // 注意：由于发生折叠，不需要再加上padding.top（因为padding.top=0）
            child_y_offset = layout_box.box_model.content.y + collapsed_margin;
            // 更新y：由于margin折叠，y应该从折叠后的margin开始
            // 这样后续子元素的y计算会正确
            y = collapsed_margin;
        } else {
            // 正常情况：子元素位置 = 父元素content.y + 累积y + 子元素margin.top
            // 其中y从padding.top开始累积
            child_y_offset = layout_box.box_model.content.y + y + child.box_model.margin.top;
        }

        child.box_model.content.y = child_y_offset;

        // 标记第一个子元素已处理
        is_first_visible_child = false;

        // 调试日志：记录子元素位置计算
        if (std.mem.eql(u8, parent_tag_name, "html") or std.mem.eql(u8, parent_tag_name, "body") or std.mem.eql(u8, child_tag_name, "body") or std.mem.eql(u8, child_tag_name, "h1")) {
            debugPrint("[LAYOUT] Child element: {s} (parent: {s})\n", .{ child_tag_name, parent_tag_name });
            debugPrint("  parent.content: x={d:.1}, y={d:.1}\n", .{ layout_box.box_model.content.x, layout_box.box_model.content.y });
            debugPrint("  parent.padding: left={d:.1}, top={d:.1}\n", .{ layout_box.box_model.padding.left, layout_box.box_model.padding.top });
            debugPrint("  child.margin: left={d:.1}, top={d:.1}\n", .{ child.box_model.margin.left, child.box_model.margin.top });
            debugPrint("  y (accumulated): {d:.1}\n", .{y});
            debugPrint("  child.content: x={d:.1} (was {d:.1}), y={d:.1} (was {d:.1})\n", .{
                child.box_model.content.x, old_x,
                child.box_model.content.y, old_y,
            });
        }

        // 对于文本节点，需要设置高度（确保文本高度被正确计算）
        // 注意：文本节点在block layout中应该被处理为inline元素，但当前简化实现直接在block layout中处理
        // TODO: 完整实现应该使用inline formatting context来处理文本节点
        if (child.node.node_type == .text) {
            // 文本节点的高度应该基于line-height和font-size
            // 使用父元素的line-height和font-size来计算文本高度
            if (child.position == .static and child.box_model.content.height == 0) {
                // 获取父元素的line-height
                const parent_line_height = layout_box.line_height;

                // 估算父元素的font-size（简化：根据标签名判断，实际应该从父元素的computed_style获取）
                // TODO: 完整实现需要从父元素的computed_style获取font-size
                var parent_font_size: f32 = 16.0; // 默认字体大小
                if (layout_box.node.node_type == .element) {
                    if (layout_box.node.asElement()) |elem| {
                        // 根据标签名判断font-size（简化实现）
                        if (std.mem.eql(u8, elem.tag_name, "h1")) {
                            parent_font_size = 32.0; // h1的font-size是2em = 32px
                        } else if (std.mem.eql(u8, elem.tag_name, "h2")) {
                            parent_font_size = 24.0; // h2的font-size是1.5em = 24px
                        } else if (std.mem.eql(u8, elem.tag_name, "h3")) {
                            parent_font_size = 20.0; // h3的font-size是1.17em ≈ 20px
                        }
                    }
                }

                // 计算实际行高（基于line-height和font-size）
                const actual_line_height = style_utils.computeLineHeight(parent_line_height, parent_font_size);

                // 设置文本节点高度为行高
                // 注意：这是简化实现，完整实现应该考虑文本的实际内容（多行文本需要多倍行高）
                // 但对于单行文本，行高就是文本高度
                child.box_model.content.height = actual_line_height;

                // 调试：记录文本节点高度计算
                if (std.mem.eql(u8, parent_tag_name, "body") or std.mem.eql(u8, parent_tag_name, "h1") or std.mem.eql(u8, parent_tag_name, "p")) {
                    const text_content = child.node.data.text;
                    const text_preview = if (text_content.len > 20) text_content[0..20] else text_content;
                    debugPrint("  [TEXT HEIGHT] text: \"{s}...\", font_size={d:.1}, line_height={d:.1}, height={d:.1}\n", .{
                        text_preview,
                        parent_font_size,
                        actual_line_height,
                        child.box_model.content.height,
                    });
                }
            }
        }

        // 更新y坐标（考虑子元素的高度和margin）
        // y坐标 = 父元素padding-top + 所有前面子元素的高度和margin
        //
        // 关键点：每个block formatting context使用独立的局部y变量
        // - y初始值 = layout_box.box_model.padding.top
        // - 对于每个子元素：
        //   1. 计算位置时：child.content.y = parent.content.y + y + child.margin.top
        //   2. 更新y时：y += child的总高度（content + padding + border + margin.bottom）
        //   注意：margin-top已经在计算位置时使用，所以y更新时只需要加上元素高度和margin-bottom
        //
        // totalSize()返回content + padding + border（不包含margin）
        const child_content_height = child.box_model.totalSize().height; // content + padding + border
        const child_total_height = child_content_height + child.box_model.margin.bottom; // 加上margin-bottom
        // margin-top已经在计算位置时使用过了，所以这里只需要加上元素高度和margin-bottom
        y += child_total_height;

        // 调试日志：记录y坐标更新
        if (std.mem.eql(u8, parent_tag_name, "html") or std.mem.eql(u8, parent_tag_name, "body") or std.mem.eql(u8, child_tag_name, "body") or std.mem.eql(u8, child_tag_name, "h1") or std.mem.eql(u8, child_tag_name, "div")) {
            debugPrint("  [UPDATE Y] child: {s}, content_height={d:.1}, margin.bottom={d:.1}, total_height={d:.1}, y after={d:.1}\n", .{
                child_tag_name,
                child_content_height,
                child.box_model.margin.bottom,
                child_total_height,
                y,
            });
        }
    }

    // 3. 计算高度
    // 如果高度未设置（为0），则根据子元素计算
    if (layout_box.box_model.content.height == 0) {
        layout_box.box_model.content.height = y + layout_box.box_model.padding.bottom;
    }
}

/// 输出元素的完整布局信息（用于与Chrome对比）
pub fn printElementLayoutInfo(layout_box: *box.LayoutBox, allocator: std.mem.Allocator, stylesheets: []const parser.Stylesheet) !void {
    const cascade = @import("cascade");
    // 优先使用LayoutBox中已计算的样式（避免重复计算）
    var computed_style: *const cascade.ComputedStyle = undefined;
    var temp_style: cascade.ComputedStyle = undefined;
    var needs_deinit = false;
    if (layout_box.computed_style) |*cs| {
        computed_style = cs;
        needs_deinit = false;
    } else {
        // 向后兼容：如果样式未计算，则重新计算
        // 注意：这里每次创建新的Cascade实例，因为printElementLayoutInfo是独立函数
        // 如果需要进一步优化，可以将Cascade实例作为参数传入
        var cascade_engine = cascade.Cascade.init(allocator);
        temp_style = try cascade_engine.computeStyle(layout_box.node, stylesheets);
        computed_style = &temp_style;
        needs_deinit = true;
    }
    errdefer {
        if (needs_deinit) {
            var mutable_style: *cascade.ComputedStyle = @constCast(computed_style);
            mutable_style.deinit();
        }
    }
    defer {
        if (needs_deinit) {
            var mutable_style: *cascade.ComputedStyle = @constCast(computed_style);
            mutable_style.deinit();
        }
    }

    const tag_name = if (layout_box.node.node_type == .element)
        if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown"
    else
        "text";

    var element_id: []const u8 = "";
    var element_class: []const u8 = "";
    if (layout_box.node.node_type == .element) {
        if (layout_box.node.asElement()) |elem| {
            element_id = elem.attributes.get("id") orelse "";
            element_class = elem.attributes.get("class") orelse "";
        }
    }

    debugPrint("\n=== Element Layout Info ===\n", .{});
    debugPrint("Tag: {s}\n", .{tag_name});
    if (element_id.len > 0) {
        debugPrint("ID: {s}\n", .{element_id});
    }
    if (element_class.len > 0) {
        debugPrint("Class: {s}\n", .{element_class});
    }

    debugPrint("\nBox Model:\n", .{});
    debugPrint("  Margin: top={d:.2}, right={d:.2}, bottom={d:.2}, left={d:.2}\n", .{
        layout_box.box_model.margin.top,
        layout_box.box_model.margin.right,
        layout_box.box_model.margin.bottom,
        layout_box.box_model.margin.left,
    });
    debugPrint("  Border: top={d:.2}, right={d:.2}, bottom={d:.2}, left={d:.2}\n", .{
        layout_box.box_model.border.top,
        layout_box.box_model.border.right,
        layout_box.box_model.border.bottom,
        layout_box.box_model.border.left,
    });
    debugPrint("  Padding: top={d:.2}, right={d:.2}, bottom={d:.2}, left={d:.2}\n", .{
        layout_box.box_model.padding.top,
        layout_box.box_model.padding.right,
        layout_box.box_model.padding.bottom,
        layout_box.box_model.padding.left,
    });
    debugPrint("  Content: x={d:.2}, y={d:.2}, width={d:.2}, height={d:.2}\n", .{
        layout_box.box_model.content.x,
        layout_box.box_model.content.y,
        layout_box.box_model.content.width,
        layout_box.box_model.content.height,
    });

    const total_size = layout_box.box_model.totalSize();
    debugPrint("  Total Size: width={d:.2}, height={d:.2}\n", .{
        total_size.width,
        total_size.height,
    });

    // 计算相对于视口的实际位置
    // content.x/y已经是元素内容区域的左上角位置，不需要再减去padding/border/margin
    // 如果需要显示包含margin的位置，应该单独计算
    const actual_x = layout_box.box_model.content.x;
    const actual_y = layout_box.box_model.content.y;
    debugPrint("  Actual Position (content box): x={d:.2}, y={d:.2}\n", .{ actual_x, actual_y });

    // 如果需要显示包含margin的位置（用于调试）
    const position_with_margin_x = layout_box.box_model.content.x - layout_box.box_model.margin.left;
    const position_with_margin_y = layout_box.box_model.content.y - layout_box.box_model.margin.top;
    debugPrint("  Position (with margin): x={d:.2}, y={d:.2}\n", .{ position_with_margin_x, position_with_margin_y });

    debugPrint("\nComputed Styles:\n", .{});
    const style_utils_module = @import("style_utils");
    if (style_utils_module.getPropertyKeyword(computed_style, "display")) |display| {
        debugPrint("  display: {s}\n", .{display});
    }
    if (style_utils_module.getPropertyKeyword(computed_style, "position")) |position| {
        debugPrint("  position: {s}\n", .{position});
    }
    const width_context = style_utils_module.createUnitContext(800);
    if (style_utils_module.getPropertyLength(computed_style, "width", width_context)) |width| {
        debugPrint("  width: {d:.2}px\n", .{width});
    }
    const height_context = style_utils_module.createUnitContext(600);
    if (style_utils_module.getPropertyLength(computed_style, "height", height_context)) |height| {
        debugPrint("  height: {d:.2}px\n", .{height});
    }
    debugPrint("==========================\n\n", .{});
}

/// 在布局树中查找指定元素（通过tag、class或id）
/// 返回找到的第一个匹配的元素，如果没有找到则返回null
pub fn findElement(layout_box: *box.LayoutBox, tag_name_opt: ?[]const u8, class_name_opt: ?[]const u8, id_opt: ?[]const u8) ?*box.LayoutBox {
    // 检查当前元素是否匹配
    if (layout_box.node.node_type == .element) {
        if (layout_box.node.asElement()) |elem| {
            var matches = true;

            // 检查tag name
            if (tag_name_opt) |tag_name| {
                if (!std.mem.eql(u8, elem.tag_name, tag_name)) {
                    matches = false;
                }
            }

            // 检查class
            if (matches) {
                if (class_name_opt) |class_name| {
                    if (elem.attributes.get("class")) |class_attr| {
                        var iter = std.mem.splitSequence(u8, class_attr, " ");
                        var found = false;
                        while (iter.next()) |cls| {
                            const trimmed = std.mem.trim(u8, cls, " \t\n\r");
                            if (std.mem.eql(u8, trimmed, class_name)) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            matches = false;
                        }
                    } else {
                        matches = false;
                    }
                }
            }

            // 检查id
            if (matches) {
                if (id_opt) |id| {
                    if (elem.attributes.get("id")) |elem_id| {
                        if (!std.mem.eql(u8, elem_id, id)) {
                            matches = false;
                        }
                    } else {
                        matches = false;
                    }
                }
            }

            if (matches) {
                return layout_box;
            }
        }
    }

    // 递归查找子元素
    for (layout_box.children.items) |child| {
        if (findElement(child, tag_name_opt, class_name_opt, id_opt)) |found| {
            return found;
        }
    }

    return null;
}
