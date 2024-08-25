//! Notes app
//! Simple app for capturing notes on the command line
//! Stores in a common JSON file in the user home directory.

const default_config = @import("default_config");
const std = @import("std");
const noteOpts = @import("opts.zig");
const notesJson = @import("notes_json.zig");

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // NOTE: getenv("HOME") does not work at compile time
    const path = try std.fs.path.join(alloc, &[_][]const u8{ std.posix.getenv("HOME").?, ".zig_notes", "zig_notesdb" });
    defer alloc.free(path);

    const DEFAULT_DATA_PATH = if (default_config.USE_HOME) path else "./notes_data.json";
    var opts = noteOpts.Opts{ .DEFAULT_DATA_PATH = DEFAULT_DATA_PATH };
    defer opts.free(alloc);

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    opts.parseArgsWithAlloc(alloc, args) catch |err| {
        switch (err) {
            noteOpts.ArgParseError.ExpectedOptionArgument,
            noteOpts.ArgParseError.MissingRequiredArguments,
            noteOpts.ArgParseError.TooManyArguments,
            noteOpts.ArgParseError.InvalidOption,
            noteOpts.ArgParseError.InvalidNumber,
            noteOpts.ArgParseError.NumberOverflow,
            => std.process.exit(1),
            else => {
                try stderr.print("(E): Encountered unknown error: '{}'\n", .{err});
                std.process.exit(1);
            },
        }
    };
    if (opts.verbose) {
        try stdout.writeAll("(I): verbose mode!\n");
        try stdout.print("(I): opts: {}\n", .{opts});
    }

    var notes = notesJson.Notes.init(alloc);
    notes.loadOrCreateDataFile(opts.data_file.?, alloc) catch |err| {
        try stderr.print("(E): unable to load notes data from '{s}': {}\n", .{ opts.data_file.?, err });
        std.process.exit(1);
    };
    defer notes.deinit();
    if (opts.show_all) {
        var sorted = notesJson.SortedStringArrayMap.init(notes.sections, alloc);
        defer sorted.deinit();
        try sorted.sort();

        try stdout.writeAll("All notes:\n");
        for (sorted.sorted.items) |section| {
            try notes.format_section(section.key_ptr.*, stdout);
        }
        std.process.exit(0);
    }

    if (opts.show_note) |note_id| {
        notes.format_entry(opts.args.items[0], note_id, stdout) catch |err| {
            switch (err) {
                notesJson.NotesError.MissingSection => {
                    try stderr.print("(E): No section named: '{s}'\n", .{opts.args.items[0]});
                    std.process.exit(1);
                },
                notesJson.NotesError.IndexOutOfRange => {
                    try stderr.print("(E): Note ID '{}' out of range for section '{s}'\n", .{ note_id, opts.args.items[0] });
                    std.process.exit(1);
                },
                else => {
                    try stderr.print("(E): Encountered unknown error: '{}'\n", .{err});
                    std.process.exit(1);
                },
            }
        };
        std.process.exit(0);
    }

    if (opts.add) {
        var section = try notes.sections.getOrPut(try alloc.dupe(u8, opts.args.items[0]));
        if (!section.found_existing) {
            section.value_ptr.* = std.ArrayList([]const u8).init(alloc);
        }
        try section.value_ptr.append(try alloc.dupe(u8, opts.args.items[1]));
        notes.writeOrCreateDataFile(opts.data_file.?) catch |err| {
            try stderr.print("(E): unable to write notes data into '{s}': {}\n", .{ opts.data_file.?, err });
            std.process.exit(1);
        };
        std.process.exit(0);
    }

    if (opts.args.items.len == 1) {
        notes.format_section(opts.args.items[0], stdout) catch |err| {
            switch (err) {
                notesJson.NotesError.MissingSection => {
                    try stderr.print("(E): No section named: '{s}'\n", .{opts.args.items[0]});
                    std.process.exit(1);
                },
                else => unreachable,
            }
        };
        std.process.exit(0);
    }

    if (opts.list or opts.args.items.len == 0) {
        try stdout.print("{}\n", .{notes});
        std.process.exit(0);
    }
}
