const std = @import("std");
const allocator = @import("allocator");

test "BrowserAllocator init and deinit" {
    // 使用page_allocator作为backing，避免嵌套GPA导致的问题
    const backing = std.heap.page_allocator;

    var browser_alloc = allocator.BrowserAllocator.init(backing);
    defer browser_alloc.deinit();

    // 测试基本功能 - Allocator是结构体，不能与null比较
    _ = browser_alloc.arenaAllocator();
    _ = browser_alloc.gpaAllocator();
}

test "BrowserAllocator arena allocation" {
    // 使用page_allocator作为backing，避免嵌套GPA导致的问题
    const backing = std.heap.page_allocator;

    var browser_alloc = allocator.BrowserAllocator.init(backing);
    defer browser_alloc.deinit();

    const arena = browser_alloc.arenaAllocator();
    const ptr = try arena.alloc(u8, 100);
    // Arena分配器不需要手动释放，会在deinit时自动释放
    _ = ptr;
}

test "BrowserAllocator gpa allocation" {
    // 使用page_allocator作为backing，避免嵌套GPA导致的问题
    const backing = std.heap.page_allocator;

    var browser_alloc = allocator.BrowserAllocator.init(backing);

    const gpa_alloc = browser_alloc.gpaAllocator();
    const ptr = try gpa_alloc.alloc(u8, 100);
    // 在 deinit 之前释放内存
    gpa_alloc.free(ptr);
    browser_alloc.deinit();
}

test "BrowserAllocator multiple allocations" {
    // 使用page_allocator作为backing，避免嵌套GPA导致的问题
    const backing = std.heap.page_allocator;

    var browser_alloc = allocator.BrowserAllocator.init(backing);
    defer browser_alloc.deinit();

    const arena = browser_alloc.arenaAllocator();
    const gpa_alloc = browser_alloc.gpaAllocator();

    // Arena分配
    const ptr1 = try arena.alloc(u8, 50);
    const ptr2 = try arena.alloc(u8, 50);
    _ = ptr1;
    _ = ptr2;

    // GPA分配
    const ptr3 = try gpa_alloc.alloc(u8, 50);
    defer gpa_alloc.free(ptr3);
    const ptr4 = try gpa_alloc.alloc(u8, 50);
    defer gpa_alloc.free(ptr4);
}

test "BrowserAllocator arena allocation with strings" {
    // 使用page_allocator作为backing，避免嵌套GPA导致的问题
    const backing = std.heap.page_allocator;

    var browser_alloc = allocator.BrowserAllocator.init(backing);
    defer browser_alloc.deinit();

    const arena = browser_alloc.arenaAllocator();
    const str1 = try arena.dupe(u8, "hello");
    const str2 = try arena.dupe(u8, "world");
    _ = str1;
    _ = str2;
}

test "BrowserAllocator gpa allocation with strings" {
    // 使用page_allocator作为backing，避免嵌套GPA导致的问题
    const backing = std.heap.page_allocator;

    var browser_alloc = allocator.BrowserAllocator.init(backing);
    defer browser_alloc.deinit();

    const gpa_alloc = browser_alloc.gpaAllocator();
    const str1 = try gpa_alloc.dupe(u8, "hello");
    defer gpa_alloc.free(str1);
    const str2 = try gpa_alloc.dupe(u8, "world");
    defer gpa_alloc.free(str2);

    std.debug.assert(std.mem.eql(u8, str1, "hello"));
    std.debug.assert(std.mem.eql(u8, str2, "world"));
}
