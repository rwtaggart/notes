//! Notes app
//! Simple app for capturing notes on the command line
//! Stores in a common JSON file in the user home directory.

// --------------------------
// Data file format (JSON)
// {
//     "section A": [
//          "note A",
//          "note B"
//     ]
// }
// --------------------------

const default_config = @import("default_config");
const std = @import("std");
const noteOpts = @import("opts.zig");

const NotesError = error{
    MissingSection,
    IndexOutOfRange,
};

const SortedStringArrayMapEntry = struct {
    key_ptr: *[]const u8,
    value_ptr: *std.ArrayList([]const u8),
};

// TODO: Rename SortedStringArrayMap => SortedSectionsMap ?
const SortedStringArrayMap = struct {
    alloc: std.mem.Allocator,
    hmap: std.StringHashMap(std.ArrayList([]const u8)),
    sorted: std.ArrayList(SortedStringArrayMapEntry),

    pub fn init(map: std.StringHashMap(std.ArrayList([]const u8)), alloc: std.mem.Allocator) SortedStringArrayMap {
        var self = SortedStringArrayMap{
            .alloc = alloc,
            .hmap = map,
            .sorted = std.ArrayList(SortedStringArrayMapEntry).init(alloc),
        };
        self.hmap.lockPointers();
        return self;
    }

    pub fn deinit(self: *SortedStringArrayMap) void {
        self.sorted.deinit();
        self.hmap.unlockPointers();
    }

    pub fn sort(self: *SortedStringArrayMap) !void {
        var itr = self.hmap.iterator();
        while (itr.next()) |entry| {
            const e = SortedStringArrayMapEntry{
                .key_ptr = entry.key_ptr,
                .value_ptr = entry.value_ptr,
            };
            try self.sorted.append(e);
        }
        std.mem.sort(SortedStringArrayMapEntry, self.sorted.items, {}, SortedStringArrayMap.entryLessThan);
    }

    fn entryLessThan(_: void, lhs: SortedStringArrayMapEntry, rhs: SortedStringArrayMapEntry) bool {
        // Compare entries based on their key value
        return std.mem.lessThan(u8, lhs.key_ptr.*, rhs.key_ptr.*);
    }

    // Render formatted string of sorted key value pairs
    // Conforms with std.fmt module.
    pub fn format(
        self: SortedStringArrayMap,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        var b = std.ArrayList(u8).init(self.alloc);
        defer b.deinit();
        var bw = b.writer();

        for (self.sorted.items) |entry| {
            try bw.print(
                \\Key: {s}
                \\Values:
                \\{s}
                \\
            , .{
                entry.key_ptr.*,
                entry.value_ptr.*,
            });
        }

        try writer.print(
            \\SortedStringArrayMap Entries:
            \\
            \\{s}
        , .{
            b.items,
        });
    }
};

// TODO: Use Notes object instead of loadOrCreateDataFile function below.
// TODO: Add loadOrCreateDataFile equivalent function to Notes struct
// TODO: Rename 'Notes' => 'NotesJson' and move to new file "json_notes.zig"
const Notes = struct {
    gpa: std.mem.Allocator = undefined,
    sections: std.StringHashMap(std.ArrayList([]const u8)) = undefined,

    /// Caller owns the memory
    /// Use deinit() to free allocated memory
    pub fn init(gpa: std.mem.Allocator) Notes {
        // TODO: Store gpa allocator for use with deinit() later... ?
        return Notes{
            .gpa = gpa,
            .sections = std.StringHashMap(std.ArrayList([]const u8)).init(gpa),
        };
    }

    pub fn deinit(self: *Notes) void {
        const gpa = self.gpa;
        var section_notes = self.sections.valueIterator();
        while (section_notes.next()) |arr| {
            for (arr.items) |str| {
                // std.io.getStdOut().writer().print("deinit str: {s}\n", .{str}) catch unreachable;
                gpa.free(str);
            }
            arr.deinit();
        }
        var section_names = self.sections.keyIterator();
        while (section_names.next()) |key_str| {
            gpa.free(key_str.*);
        }
        self.sections.deinit();
    }

    /// Load or Create Notes data file
    /// TODO: remove gpa from params and use self.gpa
    pub fn loadOrCreateDataFile(self: *Notes, fname: []const u8, gpa: std.mem.Allocator) !void {
        var map = &self.sections;
        var file = std.fs.cwd().openFile(fname, .{
            .mode = .read_only, // Q: read_only or read_write ?
        }) catch |err| cr_file: {
            switch (err) {
                std.fs.File.OpenError.FileNotFound => {
                    // TODO: Create directory tree if missing.
                    // FIXME: This breaks if fname == "file.ext" (no dirname)
                    _ = try std.fs.cwd().makePath(std.fs.path.dirname(fname).?);
                    var _file = try std.fs.cwd().createFile(fname, .{
                        .read = true,
                        .exclusive = true,
                        .truncate = false, // Not required b/c of .exclusive ?
                    });
                    try _file.writeAll("{}");
                    try _file.seekTo(0);
                    break :cr_file _file;
                },
                // TODO: Handle directory path errors?
                else => return err,
            }
        };
        defer file.close();
        const stat = try file.stat();
        const fsize = stat.size;
        const contents = try file.reader().readAllAlloc(gpa, fsize);
        defer gpa.free(contents);

        const parsed = try std.json.parseFromSlice(std.json.Value, gpa, contents, .{});
        defer parsed.deinit();
        var it = parsed.value.object.iterator();
        // const w = std.io.getStdOut().writer();
        while (it.next()) |entry| {
            // try w.print("(D): entry: {s}\n", .{entry.key_ptr.*});
            const entry_key = try gpa.dupe(u8, entry.key_ptr.*);
            const map_item = try map.getOrPut(entry_key);
            if (!map_item.found_existing) {
                map_item.value_ptr.* = std.ArrayList([]const u8).init(gpa);
            }
            for (entry.value_ptr.array.items) |value| {
                const entry_value = try gpa.dupe(u8, value.string);
                try map_item.value_ptr.append(entry_value);
            }
        }
        // try w.print("(D): map count: {}\n", .{map.count()});
        // try w.print("(D): section count: {}\n", .{self.sections.count()});
    }

    pub fn stringify(self: Notes, writer: anytype) !void {
        var json_root = std.json.Value{ .object = std.json.ObjectMap.init(self.gpa) };
        defer {
            var json_it = json_root.object.iterator();
            while (json_it.next()) |entry| {
                self.gpa.free(entry.key_ptr.*);
                for (entry.value_ptr.array.items) |json_arr_item| {
                    self.gpa.free(json_arr_item.string);
                }
                entry.value_ptr.array.deinit();
            }
            json_root.object.deinit();
        }
        var sections_it = self.sections.iterator();
        while (sections_it.next()) |section| {
            var json_item = try json_root.object.getOrPut(try self.gpa.dupe(u8, section.key_ptr.*));
            if (!json_item.found_existing) {
                json_item.value_ptr.* = std.json.Value{ .array = std.json.Array.init(self.gpa) };
            }
            for (section.value_ptr.items) |arr_item| {
                try json_item.value_ptr.array.append(std.json.Value{ .string = try self.gpa.dupe(u8, arr_item) });
            }
        }
        var json_str = std.ArrayList(u8).init(self.gpa);
        defer json_str.deinit();
        try std.json.stringify(json_root, .{}, writer);
        // try writer.print("HELLO", .{});
    }

    /// Write or Create Notes data file
    pub fn writeOrCreateDataFile(self: *Notes, fname: []const u8) !void {
        var file = try std.fs.cwd().createFile(fname, .{
            .exclusive = false,
            .truncate = true,
        });
        defer file.close();
        var json_str = std.ArrayList(u8).init(self.gpa);
        defer json_str.deinit();
        try self.stringify(json_str.writer());
        try file.writeAll(json_str.items);
        // try w.print("(D): map count: {}\n", .{map.count()});
        // try w.print("(D): section count: {}\n", .{self.sections.count()});
    }

    pub fn format_section(self: Notes, section: []const u8, writer: anytype) !void {
        const entries_o = self.sections.get(section);
        if (entries_o) |entries| {
            try writer.print("'{s}' has {} notes:\n", .{ section, entries.items.len });
            for (entries.items, 0..) |note, note_idx| {
                try writer.print("  {}: {s}\n", .{ note_idx, note });
            }
        } else {
            return NotesError.MissingSection;
        }
    }

    /// Render single note entry for easy script automation or usage
    pub fn format_entry(self: Notes, section: []const u8, note_id: u16, writer: anytype) !void {
        const entries_o = self.sections.get(section);
        if (entries_o) |entries| {
            if (note_id < 0 or note_id >= entries.items.len) {
                return NotesError.IndexOutOfRange;
            }
            const note = entries.items[note_id];
            // try writer.print("'{s}' has {} notes:\n", .{ section, entries.items.len });
            try writer.print("{s}\n", .{note});
        } else {
            return NotesError.MissingSection;
        }
    }

    /// Create string formatter compatible with std.fmt package.
    /// Render list of section titles for display
    pub fn format(
        self: Notes,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        var section_str = std.ArrayList(u8).init(self.gpa);
        var s_writer = section_str.writer();
        defer section_str.deinit();
        // var section_it = self.sections.keyIterator();
        // while (section_it.next()) |section| {
        //     try s_writer.print("{s}, ", .{section.*});
        // }
        var sorted = SortedStringArrayMap.init(self.sections, self.gpa);
        defer sorted.deinit();
        try sorted.sort();
        for (sorted.sorted.items) |section| {
            try s_writer.print("{s}, ", .{section.key_ptr.*});
        }

        // TODO: Print total number of entries in header line?
        try writer.print(
            \\Notes has {} sections:
            \\  {s}
            \\
        , .{
            self.sections.count(),
            section_str.items,
        });
    }
};

// TODO: TAKE OUT
// pub fn createNotesData(fname: []const u8) !std.fs.File {
//     return try std.fs.cwd().createFile(fname, .{
//         .read = true,
//         .truncate = false,
//         .exclusive = true,
//     });
//     // TODO: Populate file with initial JSON schema
// }

/// Read notes data file into memory
/// TODO: Return a data object
// fn _loadOrCreateNotesData(map: *std.StringHashMap(std.ArrayList([]const u8)), fname: []const u8, gpa: std.mem.Allocator) !void {
//     var file = std.fs.cwd().openFile(fname, .{
//         .mode = .read_only, // Q: read_only or read_write ?
//     }) catch |err| cr_file: {
//         switch (err) {
//             std.fs.File.OpenError.FileNotFound => {
//                 // TODO: Create directory tree if missing.
//                 var _file = try std.fs.cwd().createFile(fname, .{
//                     .read = true,
//                     .exclusive = true,
//                     .truncate = false, // Not required b/c of .exclusive ?
//                 });
//                 try _file.writeAll("{}\n");
//                 try _file.seekTo(0);
//                 break :cr_file _file;
//             },
//             // TODO: Handle directory path errors?
//             else => unreachable,
//         }
//     };
//     defer file.close();
//     const stat = try file.stat();
//     const fsize = stat.size;
//     const contents = try file.reader().readAllAlloc(gpa, fsize);
//     defer gpa.free(contents);

//     const parsed = try std.json.parseFromSlice(std.json.Value, gpa, contents, .{});
//     defer parsed.deinit();
//     // _ = map;
//     // var map = std.StringHashMap(std.ArrayList([]const u8)).init(gpa);
//     var it = parsed.value.object.iterator();
//     while (it.next()) |entry| {
//         const entry_key = try gpa.dupe(u8, entry.key_ptr.*);
//         const map_item = try map.getOrPut(entry_key);
//         if (!map_item.found_existing) {
//             map_item.value_ptr.* = std.ArrayList([]const u8).init(gpa);
//         }
//         for (entry.value_ptr.array.items) |value| {
//             const entry_value = try gpa.dupe(u8, value.string);
//             try map_item.value_ptr.append(entry_value);
//         }
//     }
//     // return map;
// }

// TODO: TAKE OUT
// pub fn deinit_map(map: *std.StringHashMap(std.ArrayList([]const u8)), gpa: std.mem.Allocator) void {
//     var deinit_map_value_itr = map.valueIterator();
//     while (deinit_map_value_itr.next()) |arr| {
//         for (arr.items) |str| {
//             // std.io.getStdOut().writer().print("deinit str: {s}\n", .{str}) catch unreachable;
//             gpa.free(str);
//         }
//         arr.deinit();
//     }
//     var deinit_map_key_itr = map.keyIterator();
//     while (deinit_map_key_itr.next()) |key_str| {
//         gpa.free(key_str.*);
//     }
//     map.deinit();
// }

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

    var notes = Notes.init(alloc);
    // try _loadOrCreateNotesData(&notes.sections, opts.data_file.?, alloc);
    notes.loadOrCreateDataFile(opts.data_file.?, alloc) catch |err| {
        try stderr.print("(E): unable to load notes data from '{s}': {}\n", .{ opts.data_file.?, err });
        std.process.exit(1);
    };
    defer notes.deinit();
    // defer deinit_map(&notes, alloc);
    if (opts.show_all) {
        // try stdout.print("{}\n", .{notes});
        // std.process.exit(0);
        // var section_str = std.ArrayList(u8).init(alloc);

        var sorted = SortedStringArrayMap.init(notes.sections, alloc);
        defer sorted.deinit();
        try sorted.sort();

        try stdout.writeAll("All notes:\n");
        // var it = notes.sections.iterator();
        // while (it.next()) |section| {
        //     try notes.format_section(section.key_ptr.*, stdout);
        // }
        for (sorted.sorted.items) |section| {
            try notes.format_section(section.key_ptr.*, stdout);
        }
        std.process.exit(0);
    }

    if (opts.show_note) |note_id| {
        notes.format_entry(opts.args.items[0], note_id, stdout) catch |err| {
            switch (err) {
                NotesError.MissingSection => {
                    try stderr.print("(E): No section named: '{s}'\n", .{opts.args.items[0]});
                    std.process.exit(1);
                },
                NotesError.IndexOutOfRange => {
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
                NotesError.MissingSection => {
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

// --- TESTING ---
test "create non-existant empty notes file" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp/notes_test_create.txt";

    _ = std.fs.cwd().deleteFile(fname) catch {};

    const file = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, file);

    var notes = Notes.init(test_alloc);
    try notes.loadOrCreateDataFile(fname, test_alloc);
    defer notes.deinit();

    const created = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    if (created) |fh| {
        try expect((try fh.stat()).size == 2);
    } else |_| {
        try expect(false);
    }
    (try created).close();

    try std.fs.cwd().deleteFile(fname);

    const deleted = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, deleted);
}

test "load existing empty notes file" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp/notes_test_exists_empty.txt";

    _ = std.fs.cwd().deleteFile(fname) catch {};

    const file = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, file);

    var new_file = try std.fs.cwd().createFile(fname, .{
        .read = true,
        .exclusive = true,
        .truncate = false, // Not required b/c of .exclusive ?
    });
    defer new_file.close();
    try new_file.writeAll("{}");
    try new_file.seekTo(0);
    try expect((try new_file.stat()).size == 2);

    var notes = Notes.init(test_alloc);
    try notes.loadOrCreateDataFile(fname, test_alloc);
    defer notes.deinit();

    try expect(notes.sections.count() == 0);

    const contents = try new_file.reader().readAllAlloc(test_alloc, (try new_file.stat()).size);
    try expect(std.mem.eql(
        u8,
        contents,
        "{}",
    ));
    defer test_alloc.free(contents);

    const created = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    if (created) |fh| {
        try expect((try fh.stat()).size == 2);
    } else |_| {
        try expect(false);
    }

    try std.fs.cwd().deleteFile(fname);

    const deleted = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, deleted);
}

test "load existing populated notes file" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp/notes_test_exists_populated.txt";

    _ = std.fs.cwd().deleteFile(fname) catch {};

    const file = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, file);

    var new_file = try std.fs.cwd().createFile(fname, .{
        .read = true,
        .exclusive = true,
        .truncate = false, // Not required b/c of .exclusive ?
    });
    defer new_file.close();

    const test_file_str =
        \\{
        \\  "a": ["A", "B", "C"],
        \\  "b": ["D"],
        \\  "c": []
        \\}
    ;

    try new_file.writeAll(test_file_str);
    try new_file.seekTo(0);
    // try std.io.getStdOut().writer().print("(D): fsize: {}\n", .{(try new_file.stat()).size});
    try expect((try new_file.stat()).size == 51);

    var notes = Notes.init(test_alloc);
    try notes.loadOrCreateDataFile(fname, test_alloc);
    defer notes.deinit();

    try std.io.getStdOut().writer().print("(D): section count: {}\n", .{notes.sections.count()});
    try expect(notes.sections.count() == 3);
    try expect(notes.sections.get("a").?.items.len == 3);

    const contents = try new_file.reader().readAllAlloc(test_alloc, (try new_file.stat()).size);
    try expect(std.mem.eql(
        u8,
        contents,
        test_file_str,
    ));
    defer test_alloc.free(contents);

    const created = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    if (created) |fh| {
        try expect((try fh.stat()).size == 51);
    } else |_| {
        try expect(false);
    }

    try std.fs.cwd().deleteFile(fname);

    const deleted = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, deleted);
}

test "json stringify empty notes data" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;

    var notes = Notes.init(test_alloc);
    var str = std.ArrayList(u8).init(test_alloc);
    defer str.deinit();
    try notes.stringify(str.writer());

    // const stdio = std.io.getStdOut().writer();
    // try stdio.print("(D): str: {s}\n", .{str.items});
    try expect(std.mem.eql(u8, str.items, "{}"));
}

test "write non-existant empty notes data" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;
    const test_alloc = std.testing.allocator;

    const fname = "./tmp/notes_test_create_empty_write.json";
    _ = std.fs.cwd().deleteFile(fname) catch {};

    var notes = Notes.init(test_alloc);
    var str = std.ArrayList(u8).init(test_alloc);
    defer str.deinit();
    try notes.stringify(str.writer());

    // const stdio = std.io.getStdOut().writer();
    // try stdio.print("(D): str: {s}\n", .{str.items});
    try expect(std.mem.eql(u8, str.items, "{}"));

    try notes.writeOrCreateDataFile(fname);

    const created = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    if (created) |fh| {
        try expect((try fh.stat()).size == 2);
        const contents = try fh.reader().readAllAlloc(test_alloc, (try fh.stat()).size);
        try expect(std.mem.eql(
            u8,
            contents,
            "{}",
        ));
        defer test_alloc.free(contents);
    } else |_| {
        try expect(false);
    }

    try std.fs.cwd().deleteFile(fname);
    const deleted = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, deleted);
}

test "write non-existant populated notes data" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;
    const test_alloc = std.testing.allocator;

    const expected_str =
        \\{"a":["A","B","C"]}
    ;

    const fname = "./tmp/notes_test_create_pop_write.json";
    _ = std.fs.cwd().deleteFile(fname) catch {};

    var notes = Notes.init(test_alloc);
    defer notes.deinit();
    try notes.sections.put(try test_alloc.dupe(u8, "a"), std.ArrayList([]const u8).init(test_alloc));
    const test_arr = [_][]const u8{ "A", "B", "C" };
    for (test_arr) |item| {
        try notes.sections.getPtr("a").?.append(try test_alloc.dupe(u8, item));
    }

    var str = std.ArrayList(u8).init(test_alloc);
    defer str.deinit();
    try notes.stringify(str.writer());

    // const stdio = std.io.getStdOut().writer();
    // try stdio.print("(D): str: {s}\n", .{str.items});
    try expect(std.mem.eql(u8, str.items, expected_str));

    try notes.writeOrCreateDataFile(fname);

    const created = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    if (created) |fh| {
        try expect((try fh.stat()).size == 19);
        const contents = try fh.reader().readAllAlloc(test_alloc, (try fh.stat()).size);
        try expect(std.mem.eql(
            u8,
            contents,
            expected_str,
        ));
        defer test_alloc.free(contents);
    } else |_| {
        try expect(false);
    }

    try std.fs.cwd().deleteFile(fname);
    const deleted = std.fs.cwd().openFile(fname, .{ .mode = .read_only }) catch |err| err;
    try expectError(std.fs.File.OpenError.FileNotFound, deleted);
}
