//! Notes SQLite
//! Notes interface for the SQLite database
//!
//! zig test -I /opt/homebrew/Cellar/sqlite/3.46.0/include -L /opt/homebrew/Cellar/sqlite/3.46.0/lib -lsqlite3 ./src/sqlite_db.zig
//!
//! SQLite Comments and References
//! https://www.sqlite.org/cintro.html
//!
//! Note: C-Pointer [*c] can be cast into Optional Pointer ?*
//! Note: Null-terminated C-string literals must be translated into Zig string literals with std.mem.span()

const std = @import("std");

// TODO: replace stdout with logging (?)
const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

const dbapi = @cImport({
    @cInclude("sqlite3.h");
});

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

// const NotesSql = struct {
//     // TEST 123
//     create: []const u8 = "TEST",
// };

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

pub const NotesDb = struct {
    gpa: std.mem.Allocator,
    db: ?*dbapi.sqlite3,
    db_path_z: [:0]const u8,

    fn init(gpa: std.mem.Allocator, db: ?*dbapi.sqlite3, path: []const u8) !NotesDb {
        return NotesDb{
            .gpa = gpa,
            .db = db,
            .db_path_z = try gpa.dupeZ(u8, path),
        };
    }

    fn deinit(self: *NotesDb) void {
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

    pub fn all_notes(self: NotesDb, notes: *std.ArrayList(NoteRecord)) !void {
        const sql = NotesSql{};
        var stmt: ?*dbapi.sqlite3_stmt = null;
        var sql_tail: ?*const u8 = null;

        if (self.db == null) {
            return NotesDbError.InvalidDatabase;
        }
        try self.check_rc(dbapi.sqlite3_prepare_v2(self.db, sql.find_all, sql.find_all.len, &stmt, &sql_tail), dbapi.SQLITE_OK);

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
    }

    pub fn find_section(self: NotesDb, section: []const u8, notes: *std.ArrayList(NoteRecord)) !void {
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
    }
    pub fn find_note() void {}

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

    var notes = std.ArrayList(NoteRecord).init(test_alloc);
    try notesdb.all_notes(&notes);

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

    var notes = std.ArrayList(NoteRecord).init(test_alloc);
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    try notesdb.all_notes(&notes);

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

    var notes = std.ArrayList(NoteRecord).init(test_alloc);
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    try notesdb.all_notes(&notes);
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

    var notes = std.ArrayList(NoteRecord).init(test_alloc);
    defer {
        for (notes.items) |note| {
            note.deinit();
        }
        notes.deinit();
    }
    try notesdb.find_section("B", &notes);

    try expect(notes.items.len == 1);
    try expect(notes.items[0].record_id == 2);
    try expect(eql(u8, notes.items[0].section.?, "B"));
    try expect(eql(u8, notes.items[0].note.?, "B NOTE"));
}
