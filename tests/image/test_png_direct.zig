const std = @import("std");
const png = @import("png");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个100x100的纯红色图像
    const width: u32 = 100;
    const height: u32 = 100;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);

    // 填充红色像素 (255, 0, 0, 255)
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i] = 255; // R
        pixels[i + 1] = 0; // G
        pixels[i + 2] = 0; // B
        pixels[i + 3] = 255; // A
    }

    std.debug.print("Created {d}x{d} red image ({d} pixels, {d} bytes)\n", .{ width, height, width * height, pixels.len });

    // 编码为PNG
    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 验证PNG签名
    std.debug.print("PNG data length: {d} bytes\n", .{png_data.len});
    std.debug.print("PNG signature: ", .{});
    for (png_data[0..8]) |b| {
        std.debug.print("{x:0>2} ", .{b});
    }
    std.debug.print("\n", .{});

    const expected_signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    var signature_ok = true;
    for (expected_signature, 0..) |expected, idx| {
        if (png_data[idx] != expected) {
            signature_ok = false;
            std.debug.print("ERROR: PNG signature mismatch at byte {d}: expected {x:0>2}, got {x:0>2}\n", .{ idx, expected, png_data[idx] });
        }
    }
    if (signature_ok) {
        std.debug.print("✓ PNG signature verified\n", .{});
    }

    // 保存到文件
    const test_output = "png_solid_red.png";
    const file = try std.fs.cwd().createFile(test_output, .{});
    defer file.close();
    try file.writeAll(png_data);

    std.debug.print("✓ PNG file created: {s} ({d} bytes)\n", .{ test_output, png_data.len });
    std.debug.print("Expected: 100x100 red square\n", .{});
}
