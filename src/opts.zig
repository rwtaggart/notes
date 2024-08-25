//! Opts
//! Define Command-line options and positional arguments
//!
//! USAGE:
//!   zig test src/opts.zig

const HELP_MESSAGE =
    \\ usage note [options] [section] [note]
    \\ 
    \\ POSITIONAL ARGUMENTS
    \\   section  title of section
    \\   note     title of note
    \\
    \\ OPTIONS
    \\   -h, --help              Show this help message and exit
    \\
    \\   -l, --list              List all sections
    \\   -a, --all               List all sections and notes
    \\   -n, --note   [N]        Return note with id 'N'.
    \\   -f, --force             Force add entry for given positional arguments
    \\
    \\       --data-file [path]   Path to override data file location
    \\       --show-data-file     Render path to default data file location
    \\
    \\ NOT YET SUPPORTED - Still a work in progress...
    \\   -u, --update [N]        Update note with id 'N'
    \\   -d, --delete [N]        Delete note with id 'N'
    \\   -s, --search [pattern]  Search for note matching pattern
    \\ 
;

const std = @import("std");
const maxInt = std.math.maxInt;

pub const ArgParseError = error{
    MissingRequiredArguments,
    ExpectedOptionArgument,
    TooManyArguments,
    InvalidOption,
    InvalidNumber,
    NumberOverflow,
};

pub const Opts = struct {
    verbose: bool = false,
    data_file: ?[]const u8 = null,
    show_data_file: bool = false,

    list: bool = false,
    show_all: bool = false,
    add: bool = false,
    force: bool = false,
    show_note: ?u16 = null,
    update: ?u16 = null,
    delete: ?u16 = null,
    search: ?[]const u8 = null,
    args: std.ArrayList([]const u8) = undefined,

    DEFAULT_DATA_PATH: []const u8,

    // note_id: ?u16 = null,
    // TODO: Replace 'args' array with:
    //       section: ?[]const u8 == null,
    //       entry: ?[]const u8 == null,

    // parseArgsErrMsg: ?[]const u8 = null,
    fn printMissingOptionArg(s: []const u8) !void {
        const stderr = std.io.getStdOut().writer();
        try stderr.print(
            \\(E): Missing required argument for option: {s}
            \\     See --help for expected usage.
            \\
        , .{s});
    }

    fn printTooManyArguments(s: [][]const u8) !void {
        const stderr = std.io.getStdOut().writer();
        try stderr.print(
            \\(E): Too many positional arguments provided: "{s}"
            \\     See --help for expected usage.
            \\
        , .{s});
    }

    fn printNotSupportedOptionArg(s: []const u8) !void {
        const stderr = std.io.getStdOut().writer();
        try stderr.print(
            \\(E): Option or argument is not yet supported: {s}
            \\     See --help for expected usage.
            \\
        , .{s});
    }

    pub fn parseU16(buf: []const u8) !u16 {
        const radix: u8 = 10;
        var x: u16 = 0;

        for (buf) |c| {
            const digit = charToDigit(c);

            if (digit >= radix) {
                return ArgParseError.InvalidNumber;
            }

            // x *= radix (shift left)
            var ov = @mulWithOverflow(x, radix);
            if (ov[1] != 0) return ArgParseError.NumberOverflow;

            // x += digit (add least significant digit)
            ov = @addWithOverflow(ov[0], digit);
            if (ov[1] != 0) return error.NumberOverflow;
            x = ov[0];
        }

        return x;
    }

    fn charToDigit(c: u8) u8 {
        return switch (c) {
            '0'...'9' => c - '0',
            'A'...'Z' => c - 'A' + 10,
            'a'...'z' => c - 'a' + 10,
            else => maxInt(u8),
        };
    }

    fn matchOption(arg: []const u8, short: []const u8, long: []const u8) bool {
        // TODO: Add support for optional short or long parameters.
        return std.mem.eql(u8, arg, short) or std.mem.eql(u8, arg, long);
    }

    fn checkArgValue(arg: []const u8) !void {
        const stderr = std.io.getStdErr().writer();
        if (arg[0] == '-') {
            try stderr.print("(W): Invalid option or positional argument value '{s}'.\n     Use '--force' to use this as a section name or entry value.\n", .{arg});
            return ArgParseError.InvalidOption;
        }
    }

    /// Initialize Config by parsing command-line arguments
    /// Uses STDOUT and STDERR to provide instructions directly.
    /// Follows the convention of std.process.argsAlloc() for memory management
    /// Caller owns the memory
    ///
    /// USAGE:
    ///   const args = try std.process.argsAlloc(alloc);
    ///   defer std.process.argsFree(alloc, args);
    ///   try opts.parseArgsWithAlloc(alloc, args);
    ///
    pub fn parseArgsWithAlloc(self: *Opts, gpa: std.mem.Allocator, args: [][]u8) !void {
        // FIXME: How do we handle a "missing" argument with a following valid option?
        const stdout = std.io.getStdOut().writer();
        const stderr = std.io.getStdOut().writer();
        self.args = std.ArrayList([]const u8).init(gpa);

        var argIdx: u8 = 1;
        while (argIdx < args.len) : (argIdx += 1) {
            if (matchOption(args[argIdx], "-h", "--help")) {
                try stdout.print("{s}\n", .{HELP_MESSAGE});
                std.process.exit(0);
            } else if (matchOption(args[argIdx], "", "--data-file")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                if (!self.force) {
                    try checkArgValue(args[argIdx]);
                }
                self.data_file = try gpa.dupe(u8, args[argIdx]);
                // try printNotSupportedOptionArg(args[argIdx - 1]);
            } else if (matchOption(args[argIdx], "", "--show-data-file")) {
                self.show_data_file = true;
            } else if (matchOption(args[argIdx], "-l", "--list")) {
                self.list = true;
            } else if (matchOption(args[argIdx], "-a", "--all")) {
                self.show_all = true;
            } else if (matchOption(args[argIdx], "-f", "--force")) {
                self.force = true;
            } else if (matchOption(args[argIdx], "-n", "--note")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                if (!self.force) {
                    try checkArgValue(args[argIdx]);
                }
                self.show_note = parseU16(args[argIdx]) catch |err| {
                    switch (err) {
                        ArgParseError.InvalidNumber, ArgParseError.NumberOverflow => {
                            try stderr.print("(E): Invalid entry index value: '{s}'\n", .{args[argIdx]});
                            return err;
                        },
                        else => return err,
                    }
                };
            } else if (matchOption(args[argIdx], "-u", "--update")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                if (!self.force) {
                    try checkArgValue(args[argIdx]);
                }
                self.update = parseU16(args[argIdx]) catch |err| {
                    switch (err) {
                        ArgParseError.InvalidNumber, ArgParseError.NumberOverflow => {
                            try stderr.print("(E): Invalid entry index value: '{s}'\n", .{args[argIdx]});
                            return err;
                        },
                        else => return err,
                    }
                };
                try printNotSupportedOptionArg(args[argIdx - 1]);
                std.process.exit(1);
            } else if (matchOption(args[argIdx], "-d", "--delete")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                if (!self.force) {
                    try checkArgValue(args[argIdx]);
                }
                self.delete = parseU16(args[argIdx]) catch |err| {
                    switch (err) {
                        ArgParseError.InvalidNumber, ArgParseError.NumberOverflow => {
                            try stderr.print("(E): Invalid entry index value: '{s}'\n", .{args[argIdx]});
                            return err;
                        },
                        else => return err,
                    }
                };
                try printNotSupportedOptionArg(args[argIdx - 1]);
                std.process.exit(1);
            } else if (matchOption(args[argIdx], "-s", "--search")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                if (!self.force) {
                    try checkArgValue(args[argIdx]);
                }
                self.search = try gpa.dupe(u8, args[argIdx]);
                try printNotSupportedOptionArg(args[argIdx - 1]);
                std.process.exit(1);
            } else if (matchOption(args[argIdx], "-v", "--verbose")) {
                self.verbose = true;
            } else {
                // Assume positional argument
                try self.args.append(try gpa.dupe(u8, args[argIdx]));
            }
        }

        // Set defaults
        if (self.data_file == null) {
            // TODO: Force set on Opts struct initialization!
            self.data_file = try gpa.dupe(u8, self.DEFAULT_DATA_PATH);
        }
        if (self.show_data_file) {
            try stdout.print("(I): data file: {s}\n", .{self.data_file.?});
        }

        if (self.args.items.len > 2) {
            try printTooManyArguments(self.args.items);
            return ArgParseError.ExpectedOptionArgument;
        }
        if (!self.force) {
            for (self.args.items) |arg| {
                try checkArgValue(arg);
            }
        }

        self.add = (self.update == null and self.delete == null and self.args.items.len == 2);
    }

    pub fn free(self: *Opts, gpa: std.mem.Allocator) void {
        // FIXME: How do we manage dynamic space with default values?
        if (self.data_file) |data_file| gpa.free(data_file);
        if (self.search) |search| gpa.free(search);
        // if (self.args) |args| args.deinit();
        for (self.args.items) |arg| {
            gpa.free(arg);
        }
        self.args.deinit();
    }

    /// Create string formatter compatible with std.fmt package.
    pub fn format(
        self: Opts,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            \\Config:
            \\  verbose mode: {}
            \\  data_file: {?s}
            \\  list: {}
            \\  all: {}
            \\  note: {?d}
            \\  update: {?d}
            \\  delete: {?d}
            \\  search: {?s}
            \\  args: {s}
            \\
        , .{
            self.verbose,
            self.data_file,
            self.list,
            self.show_all,
            self.show_note,
            self.update,
            self.delete,
            self.search,
            self.args.items,
        });
    }
};

test "handle option with missing required argument" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;
    const stderr = std.io.getStdErr().writer();
    // const stdout = std.io.getStdOut().writer();
    // const args_str: [][]u8 = &.{"--note"};
    var args_str = std.ArrayList([]u8).init(test_alloc);
    try args_str.append(try test_alloc.dupe(u8, "")); // Shift for program name
    try args_str.append(try test_alloc.dupe(u8, "--note"));
    defer {
        for (args_str.items) |item| {
            test_alloc.free(item);
        }
        args_str.deinit();
    }
    var opts = Opts{ .DEFAULT_DATA_PATH = "./tmp.json" };
    defer opts.free(test_alloc);

    var pass = false;
    opts.parseArgsWithAlloc(test_alloc, args_str.items) catch |err| {
        switch (err) {
            ArgParseError.ExpectedOptionArgument => {
                pass = true;
            },
            ArgParseError.MissingRequiredArguments,
            ArgParseError.TooManyArguments,
            ArgParseError.InvalidOption,
            ArgParseError.InvalidNumber,
            ArgParseError.NumberOverflow,
            => return error.UnexpectedParseError,
            else => {
                try stderr.print("(E): Encountered unknown error: '{}'\n", .{err});
                // std.process.exit(1);
                return error.UnexpectedValue;
            },
        }
    };
    try expect(pass);
}

test "handle option with incorrect required argument" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;
    const stderr = std.io.getStdErr().writer();
    // const stdout = std.io.getStdOut().writer();
    // const args_str: [][]u8 = &.{"--note"};
    var args_str = std.ArrayList([]u8).init(test_alloc);
    try args_str.append(try test_alloc.dupe(u8, "")); // Shift for program name
    try args_str.append(try test_alloc.dupe(u8, "--note"));
    try args_str.append(try test_alloc.dupe(u8, "BLARG"));
    defer {
        for (args_str.items) |item| {
            test_alloc.free(item);
        }
        args_str.deinit();
    }
    var opts = Opts{ .DEFAULT_DATA_PATH = "./tmp.json" };
    defer opts.free(test_alloc);

    var pass = false;
    opts.parseArgsWithAlloc(test_alloc, args_str.items) catch |err| {
        switch (err) {
            ArgParseError.InvalidNumber => {
                pass = true;
            },
            ArgParseError.ExpectedOptionArgument,
            ArgParseError.MissingRequiredArguments,
            ArgParseError.TooManyArguments,
            ArgParseError.InvalidOption,
            ArgParseError.NumberOverflow,
            => return error.UnexpectedParseError,
            else => {
                try stderr.print("(E): Encountered unknown error: '{}'\n", .{err});
                // std.process.exit(1);
                return error.UnexpectedValue;
            },
        }
    };
    try expect(pass);
}

test "handle option with correct required argument" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;
    const stderr = std.io.getStdErr().writer();
    // const stdout = std.io.getStdOut().writer();
    // const args_str: [][]u8 = &.{"--note"};
    var args_str = std.ArrayList([]u8).init(test_alloc);
    try args_str.append(try test_alloc.dupe(u8, "")); // Shift for program name
    try args_str.append(try test_alloc.dupe(u8, "--note"));
    try args_str.append(try test_alloc.dupe(u8, "1"));
    defer {
        for (args_str.items) |item| {
            test_alloc.free(item);
        }
        args_str.deinit();
    }
    var opts = Opts{ .DEFAULT_DATA_PATH = "./tmp.json" };
    defer opts.free(test_alloc);

    opts.parseArgsWithAlloc(test_alloc, args_str.items) catch |err| {
        switch (err) {
            ArgParseError.ExpectedOptionArgument,
            ArgParseError.MissingRequiredArguments,
            ArgParseError.TooManyArguments,
            ArgParseError.InvalidOption,
            ArgParseError.InvalidNumber,
            ArgParseError.NumberOverflow,
            => return error.UnexpectedParseError,
            else => {
                try stderr.print("(E): Encountered unknown error: '{}'\n", .{err});
                // std.process.exit(1);
                return error.UnexpectedValue;
            },
        }
    };
    try expect(opts.show_note == 1);
}
