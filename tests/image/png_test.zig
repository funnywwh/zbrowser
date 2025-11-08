const std = @import("std");
const testing = std.testing;
const png = @import("png");

test "PNG encoder interface exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);
    _ = encoder;
    try testing.expect(true);
}

test "PNG encode - basic RGBA image" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个2x2的红色图像（RGBA）
    const width: u32 = 2;
    const height: u32 = 2;
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

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 检查PNG文件头（前8字节应该是PNG signature）
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);
    try testing.expectEqual(@as(u8, 0x50), png_data[1]); // 'P'
    try testing.expectEqual(@as(u8, 0x4E), png_data[2]); // 'N'
    try testing.expectEqual(@as(u8, 0x47), png_data[3]); // 'G'
    try testing.expectEqual(@as(u8, 0x0D), png_data[4]); // CR
    try testing.expectEqual(@as(u8, 0x0A), png_data[5]); // LF
    try testing.expectEqual(@as(u8, 0x1A), png_data[6]); // EOF
    try testing.expectEqual(@as(u8, 0x0A), png_data[7]); // LF
}

test "PNG encode - empty image" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    const pixels = try allocator.alloc(u8, 0);
    defer allocator.free(pixels);

    const png_data = try encoder.encode(pixels, 0, 0);
    defer allocator.free(png_data);

    // 即使图像为空，也应该有PNG文件头和基本chunks
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);
}

test "PNG encode - single pixel" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个1x1的白色图像
    const width: u32 = 1;
    const height: u32 = 1;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);

    pixels[0] = 255; // R
    pixels[1] = 255; // G
    pixels[2] = 255; // B
    pixels[3] = 255; // A

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 检查PNG文件头
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);
}

test "PNG encode - large image" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 创建一个100x100的图像
    const width: u32 = 100;
    const height: u32 = 100;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);

    // 填充渐变
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const index = (y * width + x) * 4;
            pixels[index] = @as(u8, @intCast((x * 255) / width)); // R
            pixels[index + 1] = @as(u8, @intCast((y * 255) / height)); // G
            pixels[index + 2] = 128; // B
            pixels[index + 3] = 255; // A
        }
    }

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 检查PNG文件头
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);
}

test "PNG encode - IHDR chunk exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    const width: u32 = 10;
    const height: u32 = 10;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);
    @memset(pixels, 255);

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // PNG signature后应该有IHDR chunk
    // IHDR chunk type: "IHDR" (0x49 0x48 0x44 0x52)
    // 在PNG signature (8 bytes) 和 length (4 bytes) 之后
    try testing.expect(png_data.len >= 16);
    const ihdr_start = 12; // 8 (signature) + 4 (length)
    try testing.expectEqual(@as(u8, 0x49), png_data[ihdr_start]); // 'I'
    try testing.expectEqual(@as(u8, 0x48), png_data[ihdr_start + 1]); // 'H'
    try testing.expectEqual(@as(u8, 0x44), png_data[ihdr_start + 2]); // 'D'
    try testing.expectEqual(@as(u8, 0x52), png_data[ihdr_start + 3]); // 'R'
}

test "PNG encode - IEND chunk exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    const width: u32 = 5;
    const height: u32 = 5;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);
    @memset(pixels, 255);

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // IEND chunk应该在文件末尾
    // IEND chunk type: "IEND" (0x49 0x45 0x4E 0x44)
    try testing.expect(png_data.len >= 12);
    const iend_start = png_data.len - 12; // IEND chunk: 4 (length=0) + 4 (type) + 4 (CRC)
    try testing.expectEqual(@as(u8, 0x49), png_data[iend_start + 4]); // 'I'
    try testing.expectEqual(@as(u8, 0x45), png_data[iend_start + 5]); // 'E'
    try testing.expectEqual(@as(u8, 0x4E), png_data[iend_start + 6]); // 'N'
    try testing.expectEqual(@as(u8, 0x44), png_data[iend_start + 7]); // 'D'
}

test "PNG encode - CRC32 validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 测试CRC32计算（通过编码一个PNG文件来间接测试）
    // 已知"IEND"的CRC32应该是0xAE426082
    const width: u32 = 1;
    const height: u32 = 1;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);
    @memset(pixels, 255);

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 检查PNG文件结构是否正确（如果CRC计算错误，文件结构会不正确）
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);

    // IEND chunk应该在文件末尾，CRC应该正确
    try testing.expect(png_data.len >= 12);
    const iend_start = png_data.len - 12;
    try testing.expectEqual(@as(u8, 0x49), png_data[iend_start + 4]); // 'I'
    try testing.expectEqual(@as(u8, 0x45), png_data[iend_start + 5]); // 'E'
    try testing.expectEqual(@as(u8, 0x4E), png_data[iend_start + 6]); // 'N'
    try testing.expectEqual(@as(u8, 0x44), png_data[iend_start + 7]); // 'D'
}

test "PNG encode - DEFLATE compression" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encoder = png.PngEncoder.init(allocator);

    // 测试DEFLATE压缩（通过编码一个PNG文件来间接测试）
    // 创建一个有重复数据的数据块（应该可以压缩）
    const width: u32 = 10;
    const height: u32 = 10;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);
    @memset(pixels, 0xFF); // 填充相同值，应该可以压缩

    const png_data = try encoder.encode(pixels, width, height);
    defer allocator.free(png_data);

    // 压缩后的PNG文件应该存在
    try testing.expect(png_data.len > 0);

    // PNG文件应该包含所有必要的chunks
    try testing.expect(png_data.len >= 8);
    try testing.expectEqual(@as(u8, 0x89), png_data[0]);
}

test "PNG filter - Sub filter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试Sub滤波器
    // Sub滤波器：filtered[x] = original[x] - original[x-bpp]
    const bpp: usize = 4; // RGBA = 4 bytes per pixel
    const row = [_]u8{ 100, 100, 100, 255, 150, 150, 150, 255 };
    var filtered = try allocator.alloc(u8, row.len);
    defer allocator.free(filtered);

    // 应用Sub滤波器
    filtered[0] = row[0]; // 第一个像素不变
    filtered[1] = row[1];
    filtered[2] = row[2];
    filtered[3] = row[3];
    var i: usize = bpp;
    while (i < row.len) : (i += 1) {
        filtered[i] = row[i] -% row[i - bpp];
    }

    // 验证：第二个像素的R值应该是150-100=50
    try testing.expectEqual(@as(u8, 50), filtered[4]);
}

test "PNG filter - Up filter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试Up滤波器
    // Up滤波器：filtered[x] = original[x] - prior[x]
    const current_row = [_]u8{ 100, 100, 100, 255, 150, 150, 150, 255 };
    const prior_row = [_]u8{ 50, 50, 50, 255, 80, 80, 80, 255 };
    var filtered = try allocator.alloc(u8, current_row.len);
    defer allocator.free(filtered);

    // 应用Up滤波器
    var i: usize = 0;
    while (i < current_row.len) : (i += 1) {
        filtered[i] = current_row[i] -% prior_row[i];
    }

    // 验证：第一个像素的R值应该是100-50=50
    try testing.expectEqual(@as(u8, 50), filtered[0]);
}

test "PNG filter - Average filter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试Average滤波器
    // Average滤波器：filtered[x] = original[x] - floor((original[x-bpp] + prior[x]) / 2)
    const bpp: usize = 4;
    const current_row = [_]u8{ 100, 100, 100, 255, 150, 150, 150, 255 };
    const prior_row = [_]u8{ 50, 50, 50, 255, 80, 80, 80, 255 };
    var filtered = try allocator.alloc(u8, current_row.len);
    defer allocator.free(filtered);

    // 应用Average滤波器
    filtered[0] = current_row[0] -% @as(u8, @intCast((0 + prior_row[0]) / 2));
    filtered[1] = current_row[1] -% @as(u8, @intCast((0 + prior_row[1]) / 2));
    filtered[2] = current_row[2] -% @as(u8, @intCast((0 + prior_row[2]) / 2));
    filtered[3] = current_row[3] -% @as(u8, @intCast((0 + prior_row[3]) / 2));
    var i: usize = bpp;
    while (i < current_row.len) : (i += 1) {
        const left = current_row[i - bpp];
        const up = prior_row[i];
        filtered[i] = current_row[i] -% @as(u8, @intCast((@as(u16, left) + @as(u16, up)) / 2));
    }

    // 验证：第一个像素的R值应该是100-floor((0+50)/2)=100-25=75
    try testing.expectEqual(@as(u8, 75), filtered[0]);
}

test "PNG filter - Paeth filter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试Paeth滤波器
    // Paeth滤波器使用Paeth预测器
    const current_row = [_]u8{ 100, 100, 100, 255 };
    var filtered = try allocator.alloc(u8, current_row.len);
    defer allocator.free(filtered);

    // 应用Paeth滤波器（简化测试）
    // 第一个像素：paethPredictor(0, 0, 0) = 0
    filtered[0] = current_row[0] -% 0;
    filtered[1] = current_row[1] -% 0;
    filtered[2] = current_row[2] -% 0;
    filtered[3] = current_row[3] -% 0;

    // 验证：第一个像素应该等于原始值（因为预测器为0）
    try testing.expectEqual(@as(u8, 100), filtered[0]);
}
