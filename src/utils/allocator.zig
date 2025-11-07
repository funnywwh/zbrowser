const std = @import("std");

/// 浏览器专用分配器，结合Arena和GPA
pub const BrowserAllocator = struct {
    arena: std.heap.ArenaAllocator,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    gpa_allocator: std.mem.Allocator,

    pub fn init(backing_allocator: std.mem.Allocator) BrowserAllocator {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        return .{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
            .gpa = gpa,
            .gpa_allocator = gpa.allocator(),
        };
    }

    /// 返回Arena分配器（用于DOM节点等生命周期长的对象）
    pub fn arenaAllocator(self: *BrowserAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// 返回GPA分配器（用于临时对象）
    pub fn gpaAllocator(self: *BrowserAllocator) std.mem.Allocator {
        return self.gpa_allocator;
    }

    pub fn deinit(self: *BrowserAllocator) void {
        self.arena.deinit();
        _ = self.gpa.deinit();
    }
};
