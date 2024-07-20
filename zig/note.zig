//! Notes app
//! Simple app for capturing notes on the command line
//! Stores in a common JSON file in the user home directory.

// --------------------------
// TODO:
//
// Actions:
//    add
//    update
//    delete
//    search (find)
//    list
//
// Options:
//    ~data file name (?)~
//    data file path
// --------------------------

// --------------------------
// Data file format
// {
//     "section A": [
//          "note A",
//          "note B"
//     ]
// }
// --------------------------

const std = @import("std");
const maxInt = std.math.maxInt;

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
    \\   -u, --update [N]        Update note with id 'N'
    \\   -d, --delete [N]        Delete note with id 'N'
    \\   -s, --search [pattern]  Search for note matching pattern
    \\
    \\       --data-file [path]   Path to override data file location
;

const DEFAULT_DATA_PATH = "notes_data.json";

const ArgParseError = error{
    MissingRequiredArguments,
    ExpectedOptionArgument,
    TooManyArguments,
};

const Opts = struct {
    verbose: bool = false,
    data_file: ?[]const u8 = null,

    list: bool = false,
    show_all: bool = false,
    show_note: ?u16 = null,
    update: ?u16 = null,
    delete: ?u16 = null,
    search: ?[]const u8 = null,
    args: std.ArrayList([]const u8) = undefined,
    // note_id: ?u16 = null,

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
                return error.InvalidChar;
            }

            // x *= radix (shift left)
            var ov = @mulWithOverflow(x, radix);
            if (ov[1] != 0) return error.OverFlow;

            // x += digit (add least significant digit)
            ov = @addWithOverflow(ov[0], digit);
            if (ov[1] != 0) return error.OverFlow;
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

    fn checkArg(arg: []const u8, short: []const u8, long: []const u8) bool {
        // TODO: Add support for optional short or long parameters.
        return std.mem.eql(u8, arg, short) or std.mem.eql(u8, arg, long);
    }

    /// Initialize Config by parsing command-line arguments
    /// Uses STDOUT and STDERR to provide instructions directly.
    /// Follows the convention of std.process.argsAlloc() for memory management
    /// Caller owns the memory
    fn parseArgsWithAlloc(self: *Opts, gpa: std.mem.Allocator) !void {
        // FIXME: How do we handle a "missing" argument with a following valid option?
        const stdout = std.io.getStdOut().writer();
        self.args = std.ArrayList([]const u8).init(gpa);
        // const stderr = std.io.getStdOut().writer();

        const args = try std.process.argsAlloc(gpa);
        defer std.process.argsFree(gpa, args);

        var argIdx: u8 = 1;
        while (argIdx < args.len) : (argIdx += 1) {
            if (checkArg(args[argIdx], "-h", "--help")) {
                try stdout.print("{s}\n", .{HELP_MESSAGE});
                std.process.exit(1);
            } else if (checkArg(args[argIdx], "", "--data-file")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg("--data-file");
                    return ArgParseError.ExpectedOptionArgument;
                }
                const arg_str = args[argIdx];
                self.data_file = try gpa.dupe(u8, arg_str);
                try printNotSupportedOptionArg("--data-file");
            } else if (checkArg(args[argIdx], "-l", "--list")) {
                self.list = true;
            } else if (checkArg(args[argIdx], "-a", "--all")) {
                self.show_all = true;
            } else if (checkArg(args[argIdx], "-n", "--note")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg("--note (-n)");
                    return ArgParseError.ExpectedOptionArgument;
                }
                self.show_note = try parseU16(args[argIdx]);
            } else if (checkArg(args[argIdx], "-u", "--update")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg("--update (-u)");
                    return ArgParseError.ExpectedOptionArgument;
                }
                self.update = try parseU16(args[argIdx]);
            } else if (checkArg(args[argIdx], "-d", "--delete")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                self.delete = try parseU16(args[argIdx]);
            } else if (checkArg(args[argIdx], "-s", "--search")) {
                argIdx += 1;
                if (argIdx >= args.len) {
                    try printMissingOptionArg(args[argIdx - 1]);
                    return ArgParseError.ExpectedOptionArgument;
                }
                self.search = try gpa.dupe(u8, args[argIdx]);
            } else if (checkArg(args[argIdx], "-v", "--verbose")) {
                self.verbose = true;
            } else {
                // Assume positional argument
                try self.args.append(try gpa.dupe(u8, args[argIdx]));
            }
        }

        // Set defaults
        if (self.data_file == null) {
            self.data_file = try gpa.dupe(u8, DEFAULT_DATA_PATH);
        }

        if (self.args.items.len > 2) {
            try printTooManyArguments(self.args.items);
            return ArgParseError.ExpectedOptionArgument;
        }
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

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    var opts = Opts{};
    defer opts.free(alloc);
    try opts.parseArgsWithAlloc(alloc);
    if (opts.verbose) {
        try stdout.writeAll("(I): verbose mode!\n");
        try stdout.print("(I): opts: {}\n", .{opts});
    }
}
