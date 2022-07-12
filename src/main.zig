const std = @import("std");
const testing = std.testing;

const Error = error{
    SyntaxError,
};

const Value = union(enum) {
    Null,
    Boolean: bool,
    String: []const u8,
};

pub const Parser = struct {
    alloc: std.mem.Allocator,
    buf: []const u8,
    cur: usize,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, buf: []const u8) Parser {
        return .{ .alloc = alloc, .buf = buf, .cur = 0 };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.deinit();
    }

    pub fn parse(self: *Parser) !Value {
        self.skipWhitespace();

        const p = self.buf[0];
        return switch (p) {
            'n' => Value{ .Null = try self.parseNull() },
            't', 'f' => Value{ .Boolean = try self.parseBoolean() },
            '"' => Value{ .String = try self.parseString() },
            else => Error.SyntaxError,
        };
    }

    fn parseNull(self: *Parser) Error!void {
        const v = self.peek(4) orelse return Error.SyntaxError;

        if (std.mem.eql(u8, v, "null")) {
            return;
        }

        return Error.SyntaxError;
    }

    fn parseBoolean(self: *Parser) Error!bool {
        switch (self.buf[self.cur]) {
            't' => {
                const v = self.peek(4) orelse return Error.SyntaxError;

                return std.mem.eql(u8, v, "true");
            },
            'f' => {
                const v = self.peek(5) orelse return Error.SyntaxError;

                return !std.mem.eql(u8, v, "false");
            },
            else => return Error.SyntaxError,
        }
    }

    fn parseString(self: *Parser) Error![]const u8 {
        self.cur += 1;
        const start = self.cur;
        var end = self.cur;

        while (self.buf[end] != '"') : (end += 1) {
            if (end >= self.buf.len) {
                return Error.SyntaxError;
            }
        }

        self.cur = end;

        return self.buf[start..end];
    }

    pub fn peek(self: *Self, n: usize) ?[]const u8 {
        if (self.buf.len < n) {
            return null;
        }

        return self.buf[0..n];
    }

    fn skipWhitespace(self: *Self) void {
        while (true) {
            switch (self.buf[self.cur]) {
                ' ', '\n' => {
                    self.cur += 1;
                },
                else => break,
            }
        }
    }
};

test {
    const alloc = std.testing.allocator;

    try std.testing.expectEqual(Value.Null, try Parser.init(alloc, "null").parse());
    try std.testing.expectEqual(Value{ .Boolean = true }, try Parser.init(alloc, "true").parse());
    try std.testing.expectEqual(Value{ .Boolean = false }, try Parser.init(alloc, "false").parse());
    try std.testing.expect(std.mem.eql(u8, "foo", (try Parser.init(alloc, "\"foo\"").parse()).String));
}
