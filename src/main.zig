const std = @import("std");
const testing = std.testing;

const Error = error{
    ParserError,
    AllocError,
    ParseNumberError,
};

const Value = union(enum) {
    Null,
    Boolean: bool,
    String: []const u8,
    Number: f64,
    Array: std.ArrayList(Value),
    Object: std.StringArrayHashMap(Value),

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            Value.Array => |a| {
                for (a.items) |i| {
                    var it = i;
                    it.deinit();
                }

                a.deinit();
            },
            Value.Object => |o| {
                for (o.values()) |v| {
                    var it = v;
                    it.deinit();
                }

                var obj = o;
                obj.deinit();
            },
            else => {},
        }
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
            '{' => Value{ .Object = try self.parseObject() },
            '0'...'9', '+', '-' => Value{ .Number = try self.parseNumber() },
            else => {
                return Error.ParserError;
            },
        };
    }

    fn parseNull(self: *Self) Error!void {
        const v = self.peek(4) orelse return Error.ParserError;

        if (std.mem.eql(u8, v, "null")) {
            self.cur += 3;
            return;
        }

        return Error.ParserError;
    }

    fn parseBoolean(self: *Self) Error!bool {
        switch (self.buf[self.cur]) {
            't' => {
                const v = self.peek(4) orelse return Error.ParserError;
                self.cur += 3;

                if (std.mem.eql(u8, v, "true")) {
                    return true;
                } else {
                    return Error.ParserError;
                }
            },
            'f' => {
                const v = self.peek(5) orelse return Error.ParserError;
                self.cur += 4;

                if (std.mem.eql(u8, v, "false")) {
                    return false;
                } else {
                    return Error.ParserError;
                }
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

    fn parseNumber(self: *Self) Error!f64 {
        const start = self.cur;

        while (self.peek(1)) |c| : (self.cur += 1) {
            switch (c[0]) {
                '0'...'9', 'e', '.', '+', '-' => {},
                else => {
                    self.cur -= 1;
                    break;
                },
            }
        }

        return std.fmt.parseFloat(f64, self.buf[start..self.cur]) catch return Error.ParseNumberError;
    }

    fn parseArray(self: *Parser) Error!std.ArrayList(Value) {
        var arr = std.ArrayList(Value).init(self.alloc);

        self.cur += 1;

        while (true) : (self.cur += 1) {
            self.skipWhitespace();

            switch (self.buf[self.cur]) {
                ',' => {},
                ']' => {
                    break;
                },
                else => {
                    const v = try self.parse();
                    arr.append(v) catch return Error.AllocError;
                },
            }
        }

        return arr;
    }

    fn parseObject(self: *Parser) Error!std.StringArrayHashMap(Value) {
        var map = std.StringArrayHashMap(Value).init(self.alloc);
        self.cur += 1;

        while (true) : (self.cur += 1) {
            self.skipWhitespace();

            switch (self.buf[self.cur]) {
                ',' => {},
                '}' => break,
                else => {
                    const key = try self.parseString();

                    self.skipWhitespace();
                    self.cur += 1;
                    if (self.buf[self.cur] != ':') {
                        return Error.ParserError;
                    }
                    self.cur += 1;
                    const v = try self.parse();

                    try map.put(key, v) catch Error.ParserError;
                },
            }
        }

        return map;
    }

    pub fn peek(self: *Self, n: usize) ?[]const u8 {
        if (self.buf.len < self.cur + n) {
            return null;
        }

        return self.buf[self.cur .. self.cur + n];
    }

    fn skipWhitespace(self: *Self) void {
        while (self.peek(1)) |c| {
            switch (c[0]) {
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
    try std.testing.expectEqual(Value{ .Number = 1.0 }, try Parser.init(alloc, "1.0").parse());
    try std.testing.expectEqual(Value{ .Number = -3.141592 }, try Parser.init(alloc, "-3.141592").parse());
    try std.testing.expectEqualStrings("foo", (try Parser.init(alloc, "\"foo\"").parse()).String);

    var v = try Parser.init(alloc, "[true, null, [\"foo\"], [3.141592], {\"foo\": \"bar\"}]").parse();
    defer v.deinit();
    try std.testing.expect(.Array == v);
    try std.testing.expect(.Boolean == v.Array.items[0]);
    try std.testing.expect(.Null == v.Array.items[1]);
    try std.testing.expect(.Array == v.Array.items[2]);
    try std.testing.expect(.String == v.Array.items[2].Array.items[0]);
    try std.testing.expect(.Array == v.Array.items[3]);
    try std.testing.expect(.Number == v.Array.items[3].Array.items[0]);
    try std.testing.expect(.Object == v.Array.items[4]);
}
