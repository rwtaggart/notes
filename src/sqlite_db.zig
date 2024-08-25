//! Notes SQLite
//! Notes interface for the SQLite database
//!
//! SQLite Comments and References
//! https://www.sqlite.org/cintro.html
//!
//! Note: C-Pointer [*c] can be cast into Optional Pointer ?*
//! Note: Null-terminated C-string literals must be translated into Zig string literals with std.mem.span()
//!
//! USAGE:
//!   zig test -I /opt/homebrew/Cellar/sqlite/3.46.0/include -L /opt/homebrew/Cellar/sqlite/3.46.0/lib -lsqlite3 ./src/sqlite_db.zig

const std = @import("std");
const dbapi = @cImport({
    @cInclude("sqlite3.h");
});

// TODO: replace stdout with logging (?)
// Question: how do we do logging in zig?
const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

const NotesColumns = enum(u2) {
    record_id = 0,
    section = 1,
    note_id = 2,
    note = 3,
};

pub const NoteRecord = struct {
    gpa: std.mem.Allocator,
    record_id: ?i32 = null,
    section: ?[]const u8 = null,
    note_id: ?i32 = null,
    note: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator) NoteRecord {
        return NoteRecord{
            .gpa = alloc,
        };
    }

    pub fn deinit(self: NoteRecord) void {
        if (self.section) |section| {
            self.gpa.free(section);
        }
        if (self.note) |note| {
            self.gpa.free(note);
        }
    }

    // Static functions
    fn handleText(alloc: std.mem.Allocator, ctype: i32, cidx: u8, _stmt: ?*dbapi.sqlite3_stmt, valuep: *?[]const u8) !void {
        switch (ctype) {
            dbapi.SQLITE_NULL => valuep.* = null,
            dbapi.SQLITE_TEXT => valuep.* = try alloc.dupe(u8, std.mem.span(dbapi.sqlite3_column_text(_stmt, cidx))),
            else => {
                return error.UnknownSqliteType;
            },
        }
    }

    fn handleInt(ctype: i32, cidx: u8, _stmt: ?*dbapi.sqlite3_stmt, valuep: *?i32) !void {
        switch (ctype) {
            dbapi.SQLITE_NULL => valuep.* = null,
            dbapi.SQLITE_INTEGER => valuep.* = dbapi.sqlite3_column_int(_stmt, cidx),
            else => {
                return error.UnknownSqliteType;
            },
        }
    }
};

pub const SqlError = error{
    SqliteError,
};

pub const NotesDbError = error{
    InvalidDatabase,
    InvalidSchema,
    InvalidDataType,
};

const NotesSql = struct {
    create: [:0]const u8 =
        \\CREATE TABLE IF NOT EXISTS notes (
        \\  recordId INT PRIMARY KEY NOT NULL,
        \\  section TEXT,
        \\  noteId INT,
        \\  note TEXT
        \\);
    ,

    count_records: [:0]const u8 = "SELECT COUNT(recordId) FROM notes;",

    find_all: [:0]const u8 = "SELECT * FROM notes;",
    find_section: [:0]const u8 = "SELECT * FROM notes WHERE section = '{s}';",
    find_note: [:0]const u8 = "SELECT * FROM notes WHERE section = '{s}' AND noteId = '{s}';",

    add_note: [:0]const u8 = "INSERT INTO notes VALUES ({d}, '{s}', {d}, '{s}');",

    delete_all_notes: [:0]const u8 = "DROP TABLE notes;",
};

pub const SortedSectionMapEntry = struct {
    // alloc: std.mem.Allocator,
    section_ptr: *[]const u8,
    notes_ptr: *std.ArrayList([]const u8),

    // Render formatted string of sorted key value pairs
    // Conforms with std.fmt module.
    pub fn format(
        self: SortedSectionMapEntry,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("'{s}' has {} note{s}:\n", .{ self.section_ptr.*, self.notes_ptr.items.len, if (self.notes_ptr.items.len > 1) "s" else "" });
        for (self.notes_ptr.items, 0..) |note, note_idx| {
            try writer.print("  {}: {s}\n", .{ note_idx, note });
        }
    }
};

pub const SortedSectionMap = struct {
    alloc: std.mem.Allocator,
    hmap: std.StringHashMap(std.ArrayList([]const u8)),
    sorted: std.ArrayList(SortedSectionMapEntry),

    pub fn init(map: std.StringHashMap(std.ArrayList([]const u8)), alloc: std.mem.Allocator) SortedSectionMap {
        var self = SortedSectionMap{
            .alloc = alloc,
            .hmap = map,
            .sorted = std.ArrayList(SortedSectionMapEntry).init(alloc),
        };
        self.hmap.lockPointers();
        return self;
    }

    pub fn deinit(self: *SortedSectionMap) void {
        var section_notes = self.hmap.valueIterator();
        while (section_notes.next()) |records| {
            records.deinit();
        }
        self.sorted.deinit();
        self.hmap.unlockPointers();
        self.hmap.deinit();
    }

    pub fn sort(self: *SortedSectionMap) !void {
        var itr = self.hmap.iterator();
        while (itr.next()) |entry| {
            const e = SortedSectionMapEntry{
                // .alloc = self.alloc,
                .section_ptr = entry.key_ptr,
                .notes_ptr = entry.value_ptr,
            };
            try self.sorted.append(e);
        }
        std.mem.sort(SortedSectionMapEntry, self.sorted.items, {}, SortedSectionMap.entryLessThan);
    }

    fn entryLessThan(_: void, lhs: SortedSectionMapEntry, rhs: SortedSectionMapEntry) bool {
        // Compare entries based on their key value
        return std.mem.lessThan(u8, lhs.section_ptr.*, rhs.section_ptr.*);
    }

    // // Render formatted string of sorted key value pairs
    // // Conforms with std.fmt module.
    // pub fn format(
    //     self: SortedSectionMap,
    //     comptime fmt: []const u8,
    //     options: std.fmt.FormatOptions,
    //     writer: anytype,
    // ) !void {
    //     _ = fmt;
    //     _ = options;

    //     var b = std.ArrayList(u8).init(self.alloc);
    //     defer b.deinit();
    //     var bw = b.writer();

    //     for (self.sorted.items) |entry| {
    //         try bw.print(
    //             \\Key: {s}
    //             \\Values:
    //             \\{s}
    //             \\
    //         , .{
    //             entry.key_ptr.*,
    //             entry.value_ptr.*,
    //         });
    //     }

    //     try writer.print(
    //         \\SortedStringArrayMap Entries:
    //         \\
    //         \\{s}
    //     , .{
    //         b.items,
    //     });
    // }
};

pub const NotesDb = struct {
    gpa: std.mem.Allocator,
    db: ?*dbapi.sqlite3 = null,
    db_path_z: [:0]const u8,

    pub fn init(gpa: std.mem.Allocator, db: ?*dbapi.sqlite3, path: []const u8) !NotesDb {
        // TODO: remove db from params
        _ = db;
        return NotesDb{
            .gpa = gpa,
            .db_path_z = try gpa.dupeZ(u8, path),
        };
    }

    pub fn deinit(self: *NotesDb) void {
        self.gpa.free(self.db_path_z);
    }

    fn check_rc(self: NotesDb, rc: i32, code: i32) !void {
        if (rc != code) {
            // var fname: ?[]const u8 = null;
            // _ = dbapi.sqlite3_db_filename(self.db, fname);
            try stderr.print("(E): SQL Error '{s}' '{s}'\n\n", .{
                std.mem.span(dbapi.sqlite3_errmsg(self.db)),
                self.db_path_z,
            });
            return SqlError.SqliteError;
        }
    }

    pub fn open_or_create_db(self: *NotesDb) !void {
        const sql = NotesSql{};
        var stmt: ?*dbapi.sqlite3_stmt = null;
        var sql_tail: ?*const u8 = null;

        try self.check_rc(dbapi.sqlite3_open(self.db_path_z, &self.db), dbapi.SQLITE_OK);

        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql.create, sql.create.len, &stmt, &sql_tail), dbapi.SQLITE_OK);
        try self.check_rc(dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
        try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
    }

    pub fn close_db(self: NotesDb) !void {
        // May need to pass a pointer to self => modify values
        try self.check_rc(dbapi.sqlite3_close(self.db), dbapi.SQLITE_OK);
    }

    pub fn all_notes(self: NotesDb) !std.ArrayList(NoteRecord) {
        var notes = std.ArrayList(NoteRecord).init(self.gpa);
        const sql = NotesSql{};
        var stmt: ?*dbapi.sqlite3_stmt = null;
        var sql_tail: ?*const u8 = null;

        if (self.db == null) {
            return NotesDbError.InvalidDatabase;
        }
        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql.find_all, sql.find_all.len, &stmt, &sql_tail), dbapi.SQLITE_OK);

        var irows: i32 = 0;
        var step_rc: i32 = dbapi.sqlite3_step(stmt);
        while (step_rc == dbapi.SQLITE_ROW) : (step_rc = dbapi.sqlite3_step(stmt)) {
            irows += 1;
            var record = NoteRecord.init(self.gpa);
            const col_count: i32 = dbapi.sqlite3_column_count(stmt);
            if (col_count != 4) {
                return NotesDbError.InvalidSchema;
            }
            var cidx: u8 = 0; // Only 4 columns
            while (cidx < col_count) : (cidx += 1) {
                const ctype: i32 = dbapi.sqlite3_column_type(stmt, cidx);
                switch (cidx) {
                    @intFromEnum(NotesColumns.record_id) => try NoteRecord.handleInt(ctype, cidx, stmt, &record.record_id),
                    @intFromEnum(NotesColumns.section) => try NoteRecord.handleText(self.gpa, ctype, cidx, stmt, &record.section),
                    @intFromEnum(NotesColumns.note_id) => try NoteRecord.handleInt(ctype, cidx, stmt, &record.note_id),
                    @intFromEnum(NotesColumns.note) => try NoteRecord.handleText(self.gpa, ctype, cidx, stmt, &record.note),
                    else => return NotesDbError.InvalidDataType,
                }
            }

            try notes.append(record);
        }
        try self.check_rc(step_rc, dbapi.SQLITE_DONE);
        try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
        return notes;
    }

    pub fn find_section(self: NotesDb, section: []const u8) !std.ArrayList(NoteRecord) {
        var notes = std.ArrayList(NoteRecord).init(self.gpa);
        const sql = NotesSql{};
        var stmt: ?*dbapi.sqlite3_stmt = null;
        var sql_tail: ?*const u8 = null;

        if (self.db == null) {
            return NotesDbError.InvalidDatabase;
        }
        var sql_buffer = std.ArrayList(u8).init(self.gpa);
        try sql_buffer.writer().print(sql.find_section, .{section});
        defer sql_buffer.deinit();
        const sql_z = try self.gpa.dupeZ(u8, sql_buffer.items);
        defer self.gpa.free(sql_z);
        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql_z, @intCast(sql_z.len), &stmt, &sql_tail), dbapi.SQLITE_OK);

        // TODO: pass in ArrayList as arg so caller owns the memory.
        // var notes = std.ArrayList(NoteRecord).init(self.gpa);

        var irows: i32 = 0;
        var step_rc: i32 = dbapi.sqlite3_step(stmt);
        while (step_rc == dbapi.SQLITE_ROW) : (step_rc = dbapi.sqlite3_step(stmt)) {
            irows += 1;
            var record = NoteRecord.init(self.gpa);
            const col_count: i32 = dbapi.sqlite3_column_count(stmt);
            if (col_count != 4) {
                return NotesDbError.InvalidSchema;
            }
            var cidx: u8 = 0; // Only 4 columns
            while (cidx < col_count) : (cidx += 1) {
                const ctype: i32 = dbapi.sqlite3_column_type(stmt, cidx);
                switch (cidx) {
                    @intFromEnum(NotesColumns.record_id) => try NoteRecord.handleInt(ctype, cidx, stmt, &record.record_id),
                    @intFromEnum(NotesColumns.section) => try NoteRecord.handleText(self.gpa, ctype, cidx, stmt, &record.section),
                    @intFromEnum(NotesColumns.note_id) => try NoteRecord.handleInt(ctype, cidx, stmt, &record.note_id),
                    @intFromEnum(NotesColumns.note) => try NoteRecord.handleText(self.gpa, ctype, cidx, stmt, &record.note),
                    else => return NotesDbError.InvalidDataType,
                }
            }

            try notes.append(record);
        }
        try self.check_rc(step_rc, dbapi.SQLITE_DONE);
        try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
        return notes;
    }
    // pub fn find_note(self: NotesDb, section: []const u8) !NoteRecord {
    //     // var note = NoteRecord{}
    //     var notes = std.ArrayList(NoteRecord).init(self.gpa);
    //     const sql = NotesSql{};
    //     var stmt: ?*dbapi.sqlite3_stmt = null;
    //     var sql_tail: ?*const u8 = null;

    //     if (self.db == null) {
    //         return NotesDbError.InvalidDatabase;
    //     }
    //     var sql_buffer = std.ArrayList(u8).init(self.gpa);
    //     try sql_buffer.writer().print(sql.find_note, .{section});
    //     defer sql_buffer.deinit();
    //     const sql_z = try self.gpa.dupeZ(u8, sql_buffer.items);
    //     defer self.gpa.free(sql_z);
    //     try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql_z, @intCast(sql_z.len), &stmt, &sql_tail), dbapi.SQLITE_OK);

    //     var irows: i32 = 0;
    //     var step_rc: i32 = dbapi.sqlite3_step(stmt);
    //     while (step_rc == dbapi.SQLITE_ROW) : (step_rc = dbapi.sqlite3_step(stmt)) {
    //         irows += 1;
    //         var record = NoteRecord.init(self.gpa);
    //         const col_count: i32 = dbapi.sqlite3_column_count(stmt);
    //         if (col_count != 4) {
    //             return NotesDbError.InvalidSchema;
    //         }
    //         var cidx: u8 = 0; // Only 4 columns
    //         while (cidx < col_count) : (cidx += 1) {
    //             const ctype: i32 = dbapi.sqlite3_column_type(stmt, cidx);
    //             switch (cidx) {
    //                 @intFromEnum(NotesColumns.record_id) => try NoteRecord.handleInt(ctype, cidx, stmt, &record.record_id),
    //                 @intFromEnum(NotesColumns.section) => try NoteRecord.handleText(self.gpa, ctype, cidx, stmt, &record.section),
    //                 @intFromEnum(NotesColumns.note_id) => try NoteRecord.handleInt(ctype, cidx, stmt, &record.note_id),
    //                 @intFromEnum(NotesColumns.note) => try NoteRecord.handleText(self.gpa, ctype, cidx, stmt, &record.note),
    //                 else => return NotesDbError.InvalidDataType,
    //             }
    //         }

    //         try notes.append(record);
    //     }
    //     try self.check_rc(step_rc, dbapi.SQLITE_DONE);
    //     try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
    //     return notes;
    // }
    // }

    pub fn add_note(self: *NotesDb, section: []const u8, note_id: i32, note: []const u8) !void {
        const sql = NotesSql{};
        var stmt: ?*dbapi.sqlite3_stmt = null;
        var sql_tail: ?*const u8 = null;

        if (self.db == null) {
            return NotesDbError.InvalidDatabase;
        }

        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql.count_records, sql.count_records.len, &stmt, &sql_tail), dbapi.SQLITE_OK);
        try self.check_rc(dbapi.sqlite3_step(stmt), dbapi.SQLITE_ROW);
        const col_count: i32 = dbapi.sqlite3_column_count(stmt);
        if (col_count != 1) {
            return NotesDbError.InvalidSchema;
        }
        if (dbapi.sqlite3_column_type(stmt, 0) != dbapi.SQLITE_INTEGER) {
            return NotesDbError.InvalidDataType;
        }
        const n_rows: i32 = dbapi.sqlite3_column_int(stmt, 0);
        try self.check_rc(dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
        try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);

        var sql_buffer = std.ArrayList(u8).init(self.gpa);
        try sql_buffer.writer().print(sql.add_note, .{ n_rows, section, note_id, note });
        defer sql_buffer.deinit();
        const sql_z = try self.gpa.dupeZ(u8, sql_buffer.items);
        defer self.gpa.free(sql_z);

        // TODO: use logging for debug?
        // try stdout.print("(D): SQL: {s}\n", .{sql_z});

        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql_z, @intCast(sql_z.len), &stmt, &sql_tail), dbapi.SQLITE_OK);
        try self.check_rc(dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
        try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
    }

    pub fn sort_sections(self: *NotesDb, notes: std.ArrayList(NoteRecord)) !SortedSectionMap {
        var map = std.StringHashMap(std.ArrayList([]const u8)).init(self.gpa);
        // const _notes = try self.all_notes();
        for (notes.items) |record| {
            const map_item = try map.getOrPut(record.section.?);
            if (!map_item.found_existing) {
                map_item.value_ptr.* = std.ArrayList([]const u8).init(self.gpa);
            }
            try map_item.value_ptr.append(record.note.?);
        }

        var sorted = SortedSectionMap.init(map, self.gpa);
        try sorted.sort();
        return sorted;
    }

    pub fn update_note(section: []const u8, note_id: u32) void {
        _ = section;
        _ = note_id;
    }

    pub fn delete_note(section: []const u8, note_id: u32) void {
        _ = section;
        _ = note_id;
    }

    pub fn delete_section() void {}

    pub fn delete_all_notes(self: *NotesDb) !void {
        // FIXME: This is a misnomer. It actually drops the notes table from the database.
        const sql = NotesSql{};
        var stmt: ?*dbapi.sqlite3_stmt = null;
        var sql_tail: ?*const u8 = null;

        if (self.db == null) {
            return NotesDbError.InvalidDatabase;
        }
        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql.delete_all_notes, sql.find_all.len, &stmt, &sql_tail), dbapi.SQLITE_OK);
        try self.check_rc(dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
        try self.check_rc(dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
    }
};

test "NotesSql constants" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const ns = NotesSql{};
    try expect(eql(u8, ns.find_all, "SELECT * FROM notes;"));
    try expect(eql(u8, ns.create[0..32], "CREATE TABLE IF NOT EXISTS notes"));
}

test "NotesDb create" {
    // const expect = std.testing.expect;
    // const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
}

test "NotesDb find all notes (empty)" {
    const expect = std.testing.expect;
    // const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    // var notes = std.ArrayList(NoteRecord).init(test_alloc);
    const notes = try notesdb.all_notes();

    try expect(notes.items.len == 0);
}

test "NotesDb find all notes (4 records)" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("A", 0, "FIRST NOTE");
    try notesdb.add_note("A", 1, "A NOTE");
    try notesdb.add_note("B", 0, "B NOTE");
    try notesdb.add_note("C", 0, "THIRD");

    // var notes = std.ArrayList(NoteRecord).init(test_alloc);
    // try notesdb.all_notes(&notes);
    const notes = try notesdb.all_notes();
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }

    try expect(notes.items.len == 4);
    try expect(notes.items[0].record_id == 0);
    try expect(notes.items[3].record_id == 3);
    try expect(eql(u8, notes.items[0].section.?, "A"));
    try expect(eql(u8, notes.items[0].note.?, "FIRST NOTE"));
    try expect(eql(u8, notes.items[3].note.?, "THIRD"));
}

test "NotesDb add note " {
    const expect = std.testing.expect;
    // const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("A", 0, "FIRST NOTE");

    // var notes = std.ArrayList(NoteRecord).init(test_alloc);
    // try notesdb.all_notes(&notes);
    const notes = try notesdb.all_notes();
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    try expect(notes.items.len == 1);
    try expect(notes.items[0].record_id == 0);
}

test "NotesDb find section" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("A", 0, "FIRST NOTE");
    try notesdb.add_note("A", 1, "A NOTE");
    try notesdb.add_note("B", 0, "B NOTE");
    try notesdb.add_note("C", 0, "THIRD");

    const notes = try notesdb.find_section("B");
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }

    try expect(notes.items.len == 1);
    try expect(notes.items[0].record_id == 2);
    try expect(eql(u8, notes.items[0].section.?, "B"));
    try expect(eql(u8, notes.items[0].note.?, "B NOTE"));
}

test "NotesDb sort notes" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("B", 0, "B NOTE");
    try notesdb.add_note("A", 0, "FIRST NOTE");
    try notesdb.add_note("C", 0, "THIRD");
    try notesdb.add_note("A", 1, "A NOTE");

    const notes = try notesdb.all_notes();
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    var sorted = try notesdb.sort_sections(notes);
    defer {
        sorted.deinit();
    }

    try expect(sorted.sorted.items.len == 3);
    try expect(eql(u8, sorted.sorted.items[0].section_ptr.*, "A"));
    try expect(sorted.sorted.items[0].notes_ptr.*.items.len == 2);
    try expect(eql(u8, sorted.sorted.items[2].section_ptr.*, "C"));
}

test "NotesDb sort section" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("B", 0, "B NOTE");
    try notesdb.add_note("A", 0, "FIRST NOTE");
    try notesdb.add_note("C", 0, "THIRD");
    try notesdb.add_note("A", 1, "A NOTE");

    const notes = try notesdb.find_section("A");
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    var sorted = try notesdb.sort_sections(notes);
    defer {
        sorted.deinit();
    }

    try expect(sorted.sorted.items.len == 1);
    try expect(eql(u8, sorted.sorted.items[0].section_ptr.*, "A"));
    try expect(sorted.sorted.items[0].notes_ptr.*.items.len == 2);
}

// *** CHECK ERRORS ***
test "NotesDb will not find all notes" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    // try notesdb.open_or_create_db();

    var pass = false;
    notesdb.add_note("A", 0, "FIRST NOTE") catch |err| {
        switch (err) {
            SqlError.SqliteError => pass = true,
            else => try expect(false),
        }
    };
    try expect(pass);
}

test "NotesDb will not find section" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();

    var pass = false;
    _ = notesdb.find_section("B") catch |err| {
        switch (err) {
            SqlError.SqliteError => pass = true,
            else => try expect(false),
        }
    };
    try expect(pass);
}

test "NotesDb will not add a note" {
    const expect = std.testing.expect;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();

    var pass = false;
    _ = notesdb.add_note("A", 0, "BAD NOTE") catch |err| {
        switch (err) {
            SqlError.SqliteError => pass = true,
            else => try expect(false),
        }
    };
    try expect(pass);
}

// *** CHECK PRINT OUTPUTS ***
test "Write sorted sections" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("B", 0, "B NOTE");
    try notesdb.add_note("A", 0, "FIRST NOTE");
    try notesdb.add_note("C", 0, "THIRD");
    try notesdb.add_note("A", 1, "A NOTE");

    const notes = try notesdb.all_notes();
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    var sorted = try notesdb.sort_sections(notes);
    defer {
        sorted.deinit();
    }

    try expect(sorted.sorted.items.len == 3);
    try expect(eql(u8, sorted.sorted.items[0].section_ptr.*, "A"));
    try expect(sorted.sorted.items[0].notes_ptr.*.items.len == 2);
    try expect(eql(u8, sorted.sorted.items[2].section_ptr.*, "C"));

    try stdout.writeAll("(T): TEST - all notes:\n");
    for (sorted.sorted.items) |section| {
        try stdout.print("{}", .{section});
    }
    try stdout.writeAll("\n");
}

test "Write single sorted sections" {
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    const test_alloc = std.testing.allocator;
    const fname = "./tmp_test/test_create.db";

    const db: ?*dbapi.sqlite3 = null;
    var notesdb = try NotesDb.init(test_alloc, db, fname);
    defer notesdb.deinit();
    try notesdb.open_or_create_db();
    try notesdb.delete_all_notes();
    try notesdb.close_db();
    try notesdb.open_or_create_db();

    try notesdb.add_note("B", 0, "B NOTE");
    try notesdb.add_note("A", 0, "FIRST NOTE");
    try notesdb.add_note("C", 0, "THIRD");
    try notesdb.add_note("A", 1, "A NOTE");

    const notes = try notesdb.find_section("A");
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    var sorted = try notesdb.sort_sections(notes);
    defer {
        sorted.deinit();
    }

    try expect(sorted.sorted.items.len == 1);
    try expect(eql(u8, sorted.sorted.items[0].section_ptr.*, "A"));
    try expect(sorted.sorted.items[0].notes_ptr.*.items.len == 2);

    try stdout.writeAll("(T): TEST - all notes:\n");
    for (sorted.sorted.items) |section| {
        try stdout.print("{}", .{section});
    }
    try stdout.writeAll("\n");
}
