const std = @import("std");
const box = @import("box");
const style_utils = @import("style_utils");
const parser = @import("parser");

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
    else "text";
    
    // 1. 计算宽度（考虑margin、padding和border）
    // 如果当前元素有margin，可用宽度应该减去margin
    // 注意：根据CSS规范，width属性指的是content width（在content-box模式下）
    // 对于auto宽度的块级元素：
    // - 如果containing_block.width是视口宽度（根元素），content width = containing_block.width - margin - padding - border
    // - 如果containing_block.width是父元素的content width（已经减去了padding），content width = containing_block.width - margin - border
    const available_width = containing_block.width - layout_box.box_model.margin.left - layout_box.box_model.margin.right;
    const width = calculateBlockWidth(layout_box, box.Size{ .width = available_width, .height = containing_block.height });
    // 如果width是auto（即width == available_width），那么content width应该减去padding和border
    // 但根据CSS规范，width属性指的是content width，所以对于auto宽度的元素，content width = available_width - padding - border
    // 对于设置了width的元素，width已经是content width了，不需要再减去padding和border
    // 简化实现：如果width == available_width，说明是auto宽度，需要减去padding和border
    // 注意：如果content width已经设置（>0），说明已经计算过了，不需要重新计算
    // 关键修复：如果containing_block.width等于父元素的content width（已经减去了padding），那么当前元素的content width不应该再减去padding
    // 判断方法：如果当前元素不是根元素，且containing_block.width < 视口宽度，说明containing_block.width已经是content width
    if (layout_box.box_model.content.width == 0) {
        if (width == available_width) {
            // auto宽度：需要判断containing_block.width是否已经是content width
            // 简化实现：如果当前元素不是根元素，且containing_block.width < 980（视口宽度），说明containing_block.width已经是content width
            // 此时，content width = available_width - border（不需要再减去padding，因为containing_block.width已经是content width）
            // 否则，content width = available_width - padding - border
            const is_root_element = layout_box.parent == null;
            const is_content_width = !is_root_element and containing_block.width < 980.0;
            const border_horizontal = layout_box.box_model.border.left + layout_box.box_model.border.right;
            if (is_content_width) {
                // containing_block.width已经是content width，只需要减去border
                layout_box.box_model.content.width = available_width - border_horizontal;
            } else {
                // containing_block.width是视口宽度，需要减去padding和border
                const padding_horizontal = layout_box.box_model.padding.left + layout_box.box_model.padding.right;
                layout_box.box_model.content.width = available_width - padding_horizontal - border_horizontal;
            }
        } else {
            // 设置了width：width已经是content width
            layout_box.box_model.content.width = width;
        }
    }
    // 如果content width已经设置，使用已设置的值（避免重复计算）
    
    // 调试：记录h1元素的width计算
    if (std.mem.eql(u8, tag_name, "h1")) {
        std.debug.print("[WIDTH DEBUG] h1: containing_block.width={d:.1}, available_width={d:.1}, calculated_width={d:.1}\n", .{
            containing_block.width,
            available_width,
            width,
        });
    }
    const is_root = layout_box.parent == null;
    
    if (is_root or std.mem.eql(u8, tag_name, "body") or std.mem.eql(u8, tag_name, "html")) {
        std.debug.print("[LAYOUT] Element: {s}, is_root: {}\n", .{ tag_name, is_root });
        std.debug.print("  margin: top={d:.1}, right={d:.1}, bottom={d:.1}, left={d:.1}\n", .{
            layout_box.box_model.margin.top,
            layout_box.box_model.margin.right,
            layout_box.box_model.margin.bottom,
            layout_box.box_model.margin.left,
        });
        std.debug.print("  padding: top={d:.1}, right={d:.1}, bottom={d:.1}, left={d:.1}\n", .{
            layout_box.box_model.padding.top,
            layout_box.box_model.padding.right,
            layout_box.box_model.padding.bottom,
            layout_box.box_model.padding.left,
        });
        std.debug.print("  content: x={d:.1}, y={d:.1}, width={d:.1}, height={d:.1}\n", .{
            layout_box.box_model.content.x,
            layout_box.box_model.content.y,
            layout_box.box_model.content.width,
            layout_box.box_model.content.height,
        });
        std.debug.print("  containing_block: width={d:.1}, height={d:.1}\n", .{ containing_block.width, containing_block.height });
    }

    // 2. 应用margin到位置（如果父元素存在）
    // 在块级布局中，元素的margin应该影响元素相对于父元素的位置
    // 如果父元素存在，当前元素的位置 = 父元素内容区域位置 + 父元素padding + 当前元素margin
    // 但是，由于布局是递归的，当前元素的位置应该在父元素的block.zig中计算
    // 这里只处理根元素的位置
    if (layout_box.parent == null) {
        // 根元素（html）的内容区域从(0, 0)开始
        // 根元素的margin会影响根元素的总尺寸，但不影响内容区域的位置
        layout_box.box_model.content.x = 0;
        layout_box.box_model.content.y = 0;
        if (std.mem.eql(u8, tag_name, "html")) {
            std.debug.print("[LAYOUT] Root element (html) position set to (0, 0)\n", .{});
        }
    }

    // 3. 计算子元素布局
    // 注意：这里y从padding.top开始，因为子元素的位置是相对于父元素的内容区域的
    var y: f32 = layout_box.box_model.padding.top;

    // 遍历所有子元素
    for (layout_box.children.items) |child| {
        // 跳过head、title、meta、script、style、link等元数据标签（它们不应该参与布局）
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
                    continue;
                }
            }
        }
        
        // 跳过空白文本节点（它们不应该参与布局）
        if (child.node.node_type == .text) {
            const text_content = child.node.data.text;
            var is_whitespace = true;
            for (text_content) |char| {
                if (!std.ascii.isWhitespace(char)) {
                    is_whitespace = false;
                    break;
                }
            }
            if (is_whitespace) {
                continue;
            }
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
        else "text";
        const child_tag_name = if (child.node.node_type == .element)
            if (child.node.asElement()) |elem| elem.tag_name else "unknown"
        else "text";
        
        // 调试：记录body的子元素containing_block计算
        if (std.mem.eql(u8, parent_tag_name, "body") and std.mem.eql(u8, child_tag_name, "h1")) {
            std.debug.print("[CONTAINING BLOCK] body.content.width={d:.1}, child_containing_block.width={d:.1}\n", .{
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
        child.box_model.content.y = layout_box.box_model.content.y + y + child.box_model.margin.top;
        
        // 调试日志：记录子元素位置计算
        if (std.mem.eql(u8, parent_tag_name, "html") or std.mem.eql(u8, parent_tag_name, "body") or std.mem.eql(u8, child_tag_name, "body") or std.mem.eql(u8, child_tag_name, "h1")) {
            std.debug.print("[LAYOUT] Child element: {s} (parent: {s})\n", .{ child_tag_name, parent_tag_name });
            std.debug.print("  parent.content: x={d:.1}, y={d:.1}\n", .{ layout_box.box_model.content.x, layout_box.box_model.content.y });
            std.debug.print("  parent.padding: left={d:.1}, top={d:.1}\n", .{ layout_box.box_model.padding.left, layout_box.box_model.padding.top });
            std.debug.print("  child.margin: left={d:.1}, top={d:.1}\n", .{ child.box_model.margin.left, child.box_model.margin.top });
            std.debug.print("  y (accumulated): {d:.1}\n", .{y});
            std.debug.print("  child.content: x={d:.1} (was {d:.1}), y={d:.1} (was {d:.1})\n", .{
                child.box_model.content.x, old_x,
                child.box_model.content.y, old_y,
            });
        }

        // 对于文本节点，需要设置最小高度
        if (child.node.node_type == .text) {
            // 文本节点的最小高度应该足够容纳 ascent + descent
            // 使用父元素的line-height来计算高度
            // 如果父元素存在，使用父元素的line-height；否则使用默认值
            if (child.position == .static and child.box_model.content.height == 0) {
                // 获取父元素的line-height和font-size
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
                const actual_line_height = style_utils.computeLineHeight(parent_line_height, parent_font_size);
                child.box_model.content.height = actual_line_height;
            }
        }

        // 更新y坐标（考虑子元素的高度和margin）
        // y坐标 = 父元素padding-top + 所有前面子元素的高度和margin
        // 注意：margin-top已经在计算位置时使用过了，所以这里只需要加上元素高度和margin-bottom
        // 但是，为了简化，我们加上整个元素的总高度（包括margin-top和margin-bottom）
        // 因为margin-top在计算位置时已经加到了y中，所以这里需要加上元素高度和margin-bottom
        // 但实际上，由于我们在计算位置时已经加了margin-top，所以y已经包含了margin-top
        // 因此，这里只需要加上元素高度和margin-bottom
        const child_content_height = child.box_model.totalSize().height;
        const child_total_height = child_content_height + child.box_model.margin.bottom;
        // 注意：margin-top已经在计算位置时使用过了（child.box_model.content.y = ... + y + child.box_model.margin.top）
        // 所以这里只需要加上元素高度和margin-bottom
        y += child_total_height;
        
        // 调试日志：记录y坐标更新
        if (std.mem.eql(u8, parent_tag_name, "html") or std.mem.eql(u8, parent_tag_name, "body") or std.mem.eql(u8, child_tag_name, "body") or std.mem.eql(u8, child_tag_name, "h1") or std.mem.eql(u8, child_tag_name, "div")) {
            std.debug.print("  [UPDATE Y] child: {s}, content_height={d:.1}, margin.bottom={d:.1}, total_height={d:.1}, y after={d:.1}\n", .{
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
    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(layout_box.node, stylesheets);
    defer computed_style.deinit();
    
    const tag_name = if (layout_box.node.node_type == .element)
        if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown"
    else "text";
    
    var element_id: []const u8 = "";
    var element_class: []const u8 = "";
    if (layout_box.node.node_type == .element) {
        if (layout_box.node.asElement()) |elem| {
            element_id = elem.attributes.get("id") orelse "";
            element_class = elem.attributes.get("class") orelse "";
        }
    }
    
    std.debug.print("\n=== Element Layout Info ===\n", .{});
    std.debug.print("Tag: {s}\n", .{tag_name});
    if (element_id.len > 0) {
        std.debug.print("ID: {s}\n", .{element_id});
    }
    if (element_class.len > 0) {
        std.debug.print("Class: {s}\n", .{element_class});
    }
    
    std.debug.print("\nBox Model:\n", .{});
    std.debug.print("  Margin: top={d:.2}, right={d:.2}, bottom={d:.2}, left={d:.2}\n", .{
        layout_box.box_model.margin.top,
        layout_box.box_model.margin.right,
        layout_box.box_model.margin.bottom,
        layout_box.box_model.margin.left,
    });
    std.debug.print("  Border: top={d:.2}, right={d:.2}, bottom={d:.2}, left={d:.2}\n", .{
        layout_box.box_model.border.top,
        layout_box.box_model.border.right,
        layout_box.box_model.border.bottom,
        layout_box.box_model.border.left,
    });
    std.debug.print("  Padding: top={d:.2}, right={d:.2}, bottom={d:.2}, left={d:.2}\n", .{
        layout_box.box_model.padding.top,
        layout_box.box_model.padding.right,
        layout_box.box_model.padding.bottom,
        layout_box.box_model.padding.left,
    });
    std.debug.print("  Content: x={d:.2}, y={d:.2}, width={d:.2}, height={d:.2}\n", .{
        layout_box.box_model.content.x,
        layout_box.box_model.content.y,
        layout_box.box_model.content.width,
        layout_box.box_model.content.height,
    });
    
    const total_size = layout_box.box_model.totalSize();
    std.debug.print("  Total Size: width={d:.2}, height={d:.2}\n", .{
        total_size.width,
        total_size.height,
    });
    
    // 计算相对于视口的实际位置（包括margin）
    const actual_x = layout_box.box_model.content.x - layout_box.box_model.padding.left - layout_box.box_model.border.left - layout_box.box_model.margin.left;
    const actual_y = layout_box.box_model.content.y - layout_box.box_model.padding.top - layout_box.box_model.border.top - layout_box.box_model.margin.top;
    std.debug.print("  Actual Position (with margin): x={d:.2}, y={d:.2}\n", .{ actual_x, actual_y });
    
    std.debug.print("\nComputed Styles:\n", .{});
    const style_utils_module = @import("style_utils");
    if (style_utils_module.getPropertyKeyword(&computed_style, "display")) |display| {
        std.debug.print("  display: {s}\n", .{display});
    }
    if (style_utils_module.getPropertyKeyword(&computed_style, "position")) |position| {
        std.debug.print("  position: {s}\n", .{position});
    }
    const width_context = style_utils_module.createUnitContext(800);
    if (style_utils_module.getPropertyLength(&computed_style, "width", width_context)) |width| {
        std.debug.print("  width: {d:.2}px\n", .{width});
    }
    const height_context = style_utils_module.createUnitContext(600);
    if (style_utils_module.getPropertyLength(&computed_style, "height", height_context)) |height| {
        std.debug.print("  height: {d:.2}px\n", .{height});
    }
    std.debug.print("==========================\n\n", .{});
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
