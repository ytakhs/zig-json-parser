const std = @import("std");
const testing = std.testing;

pub const Parser = struct {
    alloc: std.mem.Allocator,
    buf: []const u8,

    pub fn init(alloc: std.mem.Allocator, buf: []const u8) Parser {
        return .{ .alloc = alloc, .buf = buf };
    }

    pub fn parse(this: *Parser) !void {
        std.debug.print("{s}\n", .{this.buf});
    }
};

test {
    const alloc = std.testing.allocator;

    var parser = Parser.init(alloc, "{}");
    _ = try parser.parse();
}
