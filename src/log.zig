//! Custom Logger
//! Handles errors and warnings during testing
//! NOTE: 'zig build test' hangs when printing errors to stderr.

const std = @import("std");
const builtin = @import("builtin");

pub fn Log(comptime scope: @Type(.EnumLiteral)) type {
    // Custom logging engine compatible with zig test
    // Workaround for testing (downgrade err => warn)
    // https://ziggit.dev/t/testing-errors-and-std-log-err/2595
    const logger = std.log.scoped(scope);

    return struct {
        const Self = @This();
        // errors: u32 = 0,
        // logger: @Type(logger) = logger,

        const _err = logger.err;
        pub const warn = logger.warn;
        pub const info = logger.info;
        pub const debug = logger.debug;

        pub fn err(
            // self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            // _ = self;
            if (builtin.is_test) {
                // FIXME: error: cannot assign to constant
                // self.errors += 1;
                return Self.info(format, args);
            } else {
                return Self._err(format, args);
            }
        }
    };
}

// const Log = struct {
//     // Custom logging engine compatible with zig test
//     // Workaround for testing (downgrade err => warn)
//     // https://ziggit.dev/t/testing-errors-and-std-log-err/2595
//     errors: u8 = 0,
//     logger: @Type(),

//     pub fn init(
//         comptime scope: @Type(.EnumLiteral),
//     ) void {
//         return Log{
//             .logger = std.log.scoped(scope),
//         };
//     }

//     // pub const logger = std.log.scoped(.sqlite3);
//     // pub const err = Log.logger.err;
//     pub const warn = Log.logger.warn;
//     pub const info = Log.logger.info;
//     pub const debug = Log.logger.debug;

//     pub fn err(
//         self: Log,
//         comptime format: []const u8,
//         args: anytype,
//     ) void {
//         if (builtin.is_test) {
//             self.errors += 1;
//             return Log.info(format, args);
//         } else {
//             return Log.err(format, args);
//         }
//     }

//     pub fn reset_errors(self: Log) void {
//         self.errors = 0;
//     }
// };

// TAKE OUT – DEBUG ONLY
test "initialize test compatible logger" {
    // Expecting not to see an error
    const logger = Log(.testScope);
    logger.err("(T): A sample error\n", .{});
    // TODO: How do we observed handled errors??

    // std.testing.expect(logger.errors == 1);
    // try std.testing.expect(false);
}

test "log output" {
    // std.log.err("(T): Sample error\n", .{});
    // const logger = std.log.scoped(.options);
    // logger.err("(T): Sample scoped error\n", .{});
}
