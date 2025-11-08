const std = @import("std");
const testing = std.testing;
const png = @import("png");

test "PNG encoder - generate and verify test image" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个100x100的测试图像
    // 上半部分：红色 (255, 0, 0)
    // 下半部分：蓝色 (0, 0, 255)
    const width: u32 = 100;
    const height: u32 = 100;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);

    // 填充像素数据
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const index = (y * width + x) * 4;
            if (y < height / 2) {
                // 上半部分：红色
                pixels[index] = 255; // R
                pixels[index + 1] = 0; // G
                pixels[index + 2] = 0; // B
                pixels[index + 3] = 255; // A
            } else {
                // 下半部分：蓝色
                pixels[index] = 0; // R
                pixels[index + 1] = 0; // G
                pixels[index + 2] = 255; // B
                pixels[index + 3] = 255; // A
            }
        }
    }

    // 编码为PNG
    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 验证PNG文件头（前8字节应该是PNG signature）
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);
    try testing.expectEqual(@as(u8, 0x50), png_data[1]); // 'P'
    try testing.expectEqual(@as(u8, 0x4E), png_data[2]); // 'N'
    try testing.expectEqual(@as(u8, 0x47), png_data[3]); // 'G'
    try testing.expectEqual(@as(u8, 0x0D), png_data[4]); // CR
    try testing.expectEqual(@as(u8, 0x0A), png_data[5]); // LF
    try testing.expectEqual(@as(u8, 0x1A), png_data[6]); // EOF
    try testing.expectEqual(@as(u8, 0x0A), png_data[7]); // LF

    std.debug.print("✓ PNG signature verified\n", .{});

    // 保存到文件用于查看
    const test_output = "png_verify_test.png";
    const file = try std.fs.cwd().createFile(test_output, .{});
    defer file.close();
    try file.writeAll(png_data);

    std.debug.print("✓ PNG file created: {s} ({d} bytes)\n", .{ test_output, png_data.len });

    // 验证文件大小合理
    try testing.expect(png_data.len > 100); // 至少100字节

    // 验证IHDR块（应该在偏移13处开始）
    // IHDR块：长度(4) + "IHDR"(4) + width(4) + height(4) + bit_depth(1) + color_type(1) + compression(1) + filter(1) + interlace(1) + CRC(4)
    // 宽度应该是100 (0x00000064)
    // 高度应该是100 (0x00000064)
    // 查找"IHDR"字符串
    var found_ihdr = false;
    var i: usize = 8;
    while (i < png_data.len - 4) : (i += 1) {
        if (png_data[i] == 'I' and png_data[i + 1] == 'H' and png_data[i + 2] == 'D' and png_data[i + 3] == 'R') {
            found_ihdr = true;
            std.debug.print("✓ Found IHDR chunk at offset {d}\n", .{i});
            
            // 验证宽度和高度（IHDR后4字节是宽度，再4字节是高度）
            if (i + 12 < png_data.len) {
                const width_bytes = png_data[i + 4 .. i + 8];
                const height_bytes = png_data[i + 8 .. i + 12];
                const decoded_width = (@as(u32, width_bytes[0]) << 24) | (@as(u32, width_bytes[1]) << 16) | (@as(u32, width_bytes[2]) << 8) | @as(u32, width_bytes[3]);
                const decoded_height = (@as(u32, height_bytes[0]) << 24) | (@as(u32, height_bytes[1]) << 16) | (@as(u32, height_bytes[2]) << 8) | @as(u32, height_bytes[3]);
                std.debug.print("  Width: {d}, Height: {d}\n", .{ decoded_width, decoded_height });
                try testing.expectEqual(width, decoded_width);
                try testing.expectEqual(height, decoded_height);
            }
            break;
        }
    }
    try testing.expect(found_ihdr);

    std.debug.print("✓ PNG file verification complete\n", .{});
}

test "PNG encoder - solid color image" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个50x50的纯绿色图像
    const width: u32 = 50;
    const height: u32 = 50;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);

    // 填充绿色像素 (0, 255, 0, 255)
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i] = 0; // R
        pixels[i + 1] = 255; // G
        pixels[i + 2] = 0; // B
        pixels[i + 3] = 255; // A
    }

    // 编码为PNG
    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 验证PNG签名
    try testing.expect(png_data.len >= 8);
    const expected_signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    try testing.expectEqualSlices(u8, &expected_signature, png_data[0..8]);

    // 保存到文件
    const test_output = "png_verify_solid.png";
    const file = try std.fs.cwd().createFile(test_output, .{});
    defer file.close();
    try file.writeAll(png_data);

    std.debug.print("✓ Solid color PNG created: {s} ({d} bytes)\n", .{ test_output, png_data.len });
}

test "PNG encoder - gradient image" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个200x100的水平渐变图像
    // 从左到右：黑色 -> 白色
    const width: u32 = 200;
    const height: u32 = 100;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const index = (y * width + x) * 4;
            const gray = @as(u8, @intFromFloat((@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1))) * 255.0));
            pixels[index] = gray; // R
            pixels[index + 1] = gray; // G
            pixels[index + 2] = gray; // B
            pixels[index + 3] = 255; // A
        }
    }

    // 编码为PNG
    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 验证PNG签名
    try testing.expect(png_data.len >= 8);
    const expected_signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    try testing.expectEqualSlices(u8, &expected_signature, png_data[0..8]);

    // 保存到文件
    const test_output = "png_verify_gradient.png";
    const file = try std.fs.cwd().createFile(test_output, .{});
    defer file.close();
    try file.writeAll(png_data);

    std.debug.print("✓ Gradient PNG created: {s} ({d} bytes)\n", .{ test_output, png_data.len });
}

