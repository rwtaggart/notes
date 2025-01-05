//! Zig Logging
//! std.log
//!
//! REFERENCES:
//!
//! Overview of zig log
//! https://gist.github.com/kassane/a81d1ae2fa2e8c656b91afee8b949426
//!
//! https://medium.com/@mikecode/zig-79-return-a-function-2145cf7b9915
//! https://ziggit.dev/t/testing-errors-and-std-log-err/2595/2
//!
//! Workaround for testing (downgrade err => warn)
//! https://ziggit.dev/t/testing-errors-and-std-log-err/2595

const std = @import("std");

const CaptureLoggedError = struct {
    err_logged: bool = false,

    // FIXME: GET THIS WORKING???
    pub fn loggingHandler(self: CaptureLoggedError) fn (comptime anytype, comptime anytype, comptime anytype, anytype) void {
        return struct {
            fn handleLoggedErr(
                comptime message_level: std.log.Level,
                comptime scope: @TypeOf(.enum_literal),
                comptime format: []const u8,
                args: anytype,
            ) void {
                _ = message_level;
                _ = scope;
                _ = format;
                _ = args;
                std.debug.print("(D): loggingHandler()\n", .{});
                self.err_logged = true;
            }
        }.handleLoggedErr;
    }
};
const loggedErr = CaptureLoggedError{};

const std_options = .{
    .logFn = loggedErr.handleLoggedErr,
};

// LOGGING EXPERIMENT
const Log = struct {
    // Custom logging engine compatible with zig test
    // Workaround for testing (downgrade err => warn)
    // https://ziggit.dev/t/testing-errors-and-std-log-err/2595

    // logger = std.log.scoped(.sqlite3),
    err = std.log.err,
    warn = std.log.warn,
    info = std.log.info,
    debug = std.log.debug,

    // pub fn a() void {}
};

test "init Log" {
    const t_logger = Log{};
    std.testing.expect(t_logger.err == std.log.scoped(.sqlite3).err);
}
