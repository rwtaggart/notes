//! Notes app
//! Simple app for capturing notes on the command line
//! Stores in a common JSON file in the user home directory.
//!
//! QUESTION:
//! How do I include c-library with cImport and zig build?
//! https://discord.com/channels/605571803288698900/1274576428452548731
//!
//! BUILD
//! zig build-exe -I /opt/homebrew/Cellar/sqlite/3.46.0/include -L /opt/homebrew/Cellar/sqlite/3.46.0/lib -lsqlite3 ./src/note.zig

const default_config = @import("default_config");
const std = @import("std");
const noteOpts = @import("opts.zig");
const notesJson = @import("notes_json.zig");
const db = @import("sqlite_db.zig");

// TODO: Add custom logging
//       write custom logging function for printing errors to the terminal
//
// const std_options {
//   .logFn = noteLogFn;
// }
//
// pub fn noteLogFn(
//     comptime level: std.log.Level,
//     comptime scope: @TypeOf(.EnumLiteral),
//     comptime format: []const u8,
//     args: anytype,
// ) void {
//     // Create custom format for errors and warnings
//     // Use the default logging method for everything else.
//
//     // TODO: ADD CODE HERE
//
//     // Print the message to stderr, silently ignoring any errors
//     std.debug.lockStdErr();
//     defer std.debug.unlockStdErr();
//     const stderr = std.io.getStdErr().writer();
//     nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
// }

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // NOTE: getenv("HOME") does not work at compile time (obviously).
    const path = try std.fs.path.join(alloc, &[_][]const u8{ std.posix.getenv("HOME").?, ".zig_notes", "zig_notes.db" });
    defer alloc.free(path);

    const DEFAULT_DATA_PATH = if (default_config.USE_HOME) path else "./notes_data.db";
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

    // TODO: rename 'notesdb' => 'notes'?
    var notesdb = db.NotesDb.init(alloc, null, opts.data_file.?) catch |err| {
        try stderr.print("(E): unable to initialize notes database '{s}': {}\n", .{ opts.data_file.?, err });
        std.process.exit(1);
    };
    defer notesdb.deinit();
    notesdb.open_or_create_db() catch |err| {
        try stderr.print("(E): unable to load notes data from '{s}': {}\n", .{ opts.data_file.?, err });
        std.process.exit(1);
    };
    if (opts.show_all) {
        // TODO: rename 'notes_records' => 'notes'?
        const notes_records = notesdb.all_notes() catch |err| {
            switch (err) {
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): unable to load notes data from '{s}': {}\n", .{ opts.data_file.?, err });
                    std.process.exit(0);
                },
                else => unreachable,
            }
        };
        defer {
            for (notes_records.items) |record| {
                record.deinit();
            }
            notes_records.deinit();
        }
        var sorted = try notesdb.sort_sections(notes_records);
        defer sorted.deinit();

        try stdout.writeAll("All notes:\n");
        for (sorted.sorted.items) |section| {
            try stdout.print("{}", .{section});
        }
        std.process.exit(0);
    }

    if (opts.show_note) |note_id| {
        // TODO: use notesdb.find_note() instead?
        const notes_records = notesdb.find_section(opts.args.items[0]) catch |err| {
            switch (err) {
                db.SqlError.SqliteError,
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): No section named: '{s}'\n", .{opts.args.items[0]});
                    std.process.exit(1);
                },
                else => unreachable,
            }
        };
        defer {
            for (notes_records.items) |record| {
                record.deinit();
            }
            notes_records.deinit();
        }
        if (note_id < 0 or note_id >= notes_records.items.len) {
            try stderr.print("(E): Note ID '{d}' out of range for section '{s}'\n", .{ note_id, opts.args.items[0] });
            std.process.exit(1);
        }
        const note_record = notes_records.items[note_id];
        try stdout.print("{s}\n", .{note_record.note.?});
        std.process.exit(0);
    }

    if (opts.add) {
        const note_str = try alloc.dupe(u8, opts.args.items[1]);
        defer alloc.free(note_str);
        notesdb.add_note(opts.args.items[0], 0, note_str) catch |err| {
            switch (err) {
                db.SqlError.SqliteError,
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): unable to write notes data into '{s}': {}\n", .{ opts.data_file.?, err });
                    std.process.exit(1);
                },
                else => unreachable,
            }
        };
        std.process.exit(0);
    }

    if (opts.update) |note_id| {
        const note_str = try alloc.dupe(u8, opts.args.items[1]);
        defer alloc.free(note_str);
        notesdb.update_note(opts.args.items[0], note_id, note_str) catch |err| {
            switch (err) {
                db.NotesDbError.IndexOutOfRange => {
                    try stderr.print("(E): Note ID '{d}' out of range for section '{s}' : {}\n", .{ note_id, opts.args.items[0], err });
                    std.process.exit(1);
                },
                db.SqlError.SqliteError,
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): unable to update notes data in '{s}': {}\n", .{ opts.data_file.?, err });
                    std.process.exit(1);
                },
                else => unreachable,
            }
        };
        try stdout.print("(I): updated note in section '{s}' with id '{d}'\n", .{ opts.args.items[0], note_id });
        std.process.exit(0);
    }

    if (opts.delete) |note_id| {
        // const note_str = try alloc.dupe(u8, opts.args.items[1]);
        // defer alloc.free(note_str);
        notesdb.delete_note(opts.args.items[0], note_id) catch |err| {
            switch (err) {
                db.NotesDbError.IndexOutOfRange => {
                    try stderr.print("(E): Note ID '{d}' out of range for section '{s}' : {}\n", .{ note_id, opts.args.items[0], err });
                    std.process.exit(1);
                },
                db.SqlError.SqliteError,
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): unable to delete notes data in '{s}': {}\n", .{ opts.data_file.?, err });
                    std.process.exit(1);
                },
                else => unreachable,
            }
        };
        try stdout.print("(I): deleted note from section '{s}' with id '{d}'\n", .{ opts.args.items[0], note_id });
        std.process.exit(0);
    }

    if (opts.search) |search| {
        const notes_records = notesdb.search_notes(search) catch |err| {
            switch (err) {
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): unable to load notes data from '{s}': {}\n", .{ opts.data_file.?, err });
                    std.process.exit(0);
                },
                else => unreachable,
            }
        };
        defer {
            for (notes_records.items) |record| {
                record.deinit();
            }
            notes_records.deinit();
        }
        var sorted = try notesdb.sort_sections(notes_records);
        defer sorted.deinit();

        try stdout.print(
            "Search for '{s}' found {d} sections with {d} notes:\n",
            .{
                search,
                sorted.sorted.items.len,
                notes_records.items.len,
            },
        );
        for (sorted.sorted.items) |section| {
            try stdout.print("{}", .{section});
        }
        std.process.exit(0);
    }

    if (opts.args.items.len == 1) {
        const notes_records = notesdb.find_section(opts.args.items[0]) catch |err| {
            switch (err) {
                db.SqlError.SqliteError,
                db.NotesDbError.InvalidDatabase,
                db.NotesDbError.InvalidSchema,
                db.NotesDbError.InvalidDataType,
                => {
                    try stderr.print("(E): No section named: '{s}'\n", .{opts.args.items[0]});
                    std.process.exit(1);
                },
                else => unreachable,
            }
        };
        defer {
            for (notes_records.items) |record| {
                record.deinit();
            }
            notes_records.deinit();
        }
        var sorted = try notesdb.sort_sections(notes_records);
        defer sorted.deinit();

        for (sorted.sorted.items) |section| {
            try stdout.print("{}", .{section});
        }
        std.process.exit(0);
    }

    if (opts.list or opts.args.items.len == 0) {
        try stdout.print("{}\n", .{notesdb});
        std.process.exit(0);
    }
}
