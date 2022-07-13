const std = @import("std");
const testing = std.testing;

const Error = error{
    ParserError,
    AllocError,
};

const Value = union(enum) {
    Null,
    Boolean: bool,
    String: []const u8,
    Array: std.ArrayList(Value),

    pub fn deinit(self: *Value) void {
        self.Array.deinit();
    }
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

    pub fn parse(self: *Self) !Value {
        self.skipWhitespace();

        const p = self.buf[self.cur];
        return switch (p) {
            'n' => Value{ .Null = try self.parseNull() },
            't', 'f' => Value{ .Boolean = try self.parseBoolean() },
            '"' => Value{ .String = try self.parseString() },
            '[' => Value{ .Array = try self.parseArray() },
            else => Error.ParserError,
        };
    }

    fn parseNull(self: *Self) Error!void {
        const v = self.peek(4) orelse return Error.ParserError;

        if (std.mem.eql(u8, v, "null")) {
            return;
        }

        return Error.ParserError;
    }

    fn parseBoolean(self: *Self) Error!bool {
        switch (self.buf[self.cur]) {
            't' => {
                const v = self.peek(4) orelse return Error.ParserError;

                return std.mem.eql(u8, v, "true");
            },
            'f' => {
                const v = self.peek(5) orelse return Error.ParserError;

                return !std.mem.eql(u8, v, "false");
            },
            else => return Error.ParserError,
        }
    }

    fn parseString(self: *Self) Error![]const u8 {
        self.cur += 1;
        const start = self.cur;
        var end = self.cur;

        while (self.buf[end] != '"') : (end += 1) {
            if (end >= self.buf.len) {
                return Error.ParserError;
            }
        }

        self.cur = end;

        return self.buf[start..end];
    }

    fn parseArray(self: *Parser) Error!std.ArrayList(Value) {
        var arr = std.ArrayList(Value).init(self.alloc);

        self.cur += 1;

        while (true) : (self.cur += 1) {
            self.skipWhitespace();

            var start = self.cur;
            var end = self.cur;

            while (self.buf[end] != ',' and self.buf[end] != ']') : (end += 1) {}

            self.cur = end;

            var p = Parser.init(self.alloc, self.buf[start..end]);

            arr.append(try p.parse()) catch return Error.AllocError;

            if (self.buf[self.cur] == ']') {
                break;
            }
        }

        return arr;
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
    try std.testing.expectEqualStrings("foo", (try Parser.init(alloc, "\"foo\"").parse()).String);

    var v = try Parser.init(alloc, "[true, null, \"foo\"]").parse();
    try std.testing.expect(.Array == v);
    try std.testing.expect(.Boolean == v.Array.items[0]);
    try std.testing.expect(.Null == v.Array.items[1]);
    try std.testing.expect(.String == v.Array.items[2]);
    defer v.deinit();
}
