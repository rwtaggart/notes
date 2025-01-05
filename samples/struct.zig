//! Simple struct test
//! zig test struct.zig
//!
//! NOTE: structs must declare types with fields

const std = @import("std");

const A = struct {
    m: i32 = 10,
};

const B = struct {
    // Causes compiler error:
    // "error: use of undeclared identifier 'm1'""
    // m1 = 10,

    // declarations may be used in structs:
    pub const c = 20;
};

test "init struct" {
    const a = A{};
    const b = B{};
    _ = b;
    try std.testing.expect(a.m == 10);
    try std.testing.expect(B.c == 20);
}
