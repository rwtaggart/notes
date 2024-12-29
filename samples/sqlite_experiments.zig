//! SQLite API Examples
//! Tests and experiments for SQLite API usage
//!
//! SQLite Comments and References
//! https://www.sqlite.org/cintro.html
//!
//! Note: C-Pointer [*c] can be cast into Optional Pointer ?*
//! Note: Null-terminated C-string literals must be translated into Zig string literals with std.mem.span()
//!
//! USAGE:
//!   zig test -I /opt/homebrew/Cellar/sqlite/3.46.0/include -L /opt/homebrew/Cellar/sqlite/3.46.0/lib -lsqlite3 ./tmp/sqlite_experiments.zig
//!   zig run -I /opt/homebrew/Cellar/sqlite/3.46.0/include -L /opt/homebrew/Cellar/sqlite/3.46.0/lib -lsqlite3 sqlite_ex.zig

const std = @import("std");
const dbapi = @cImport({
    @cInclude("sqlite3.h");
});

const test_alloc = std.testing.allocator;

pub const SqlError = error{
    SqliteError,
};

pub const NotesDbError = error{
    InvalidDatabase,
    InvalidSchema,
    InvalidDataType,
    IndexOutOfRange,
};

const NotesColumns = enum(u1) {
    recordId = 0,
    note = 1,
};

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

// TODO: replace stdout with logging (?)
// Question: how do we do logging in zig?
const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

// const test_alloc = std.testing.allocator;
// const db: ?*dbapi.sqlite3 = null;
// const fname = "./tmp_test/test_create.db";
const fname = "./tmp_test/test_create_1.db";

const sql_create: [:0]const u8 =
    \\CREATE TABLE IF NOT EXISTS notes (
    \\  recordId INT PRIMARY KEY NOT NULL,
    \\  note TEXT
    \\);
;
const sql_insert: [:0]const u8 = "INSERT INTO notes VALUES ({d}, '{s}');";
const sql_insert_params: [:0]const u8 = "INSERT INTO notes VALUES (?1, ?2);";
const sql_search_params: [:0]const u8 = "SELECT * FROM notes WHERE note like ?1;";
// const sql_find_section: [:0]const u8 = "SELECT * FROM notes WHERE section = '{s}';";
const sql_delete_all_notes: [:0]const u8 = "DROP TABLE notes;";
const sql_find_all: [:0]const u8 = "SELECT * FROM notes;";

fn check_rc(db: ?*dbapi.sqlite3, rc: i32, code: i32) !void {
    if (rc != code) {
        // var fname: ?[]const u8 = null;
        // _ = dbapi.sqlite3_db_filename(self.db, fname);
        try stderr.print("(E): SQL Error '{s}'\n\n", .{
            std.mem.span(dbapi.sqlite3_errmsg(db)),
        });
        return SqlError.SqliteError;
    }
}

pub fn open_or_create_db(db: *?*dbapi.sqlite3) !void {
    var stmt: ?*dbapi.sqlite3_stmt = null;
    var sql_tail: ?*const u8 = null;

    try check_rc(db.*, dbapi.sqlite3_open(fname, db), dbapi.SQLITE_OK);
    try check_rc(db.*, dbapi.sqlite3_prepare_v2(db.*, sql_create, sql_create.len, &stmt, &sql_tail), dbapi.SQLITE_OK);
    try check_rc(db.*, dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
    try check_rc(db.*, dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
}

pub fn close_db(db: ?*dbapi.sqlite3) !void {
    // May need to pass a pointer to self => modify values
    try check_rc(db, dbapi.sqlite3_close(db), dbapi.SQLITE_OK);
}

pub fn all_notes(db: ?*dbapi.sqlite3) !void {
    var records = std.ArrayList(std.ArrayList(u8)).init(test_alloc);
    defer {
        for (records.items) |item| {
            item.deinit();
        }
        records.deinit();
    }
    var stmt: ?*dbapi.sqlite3_stmt = null;
    var sql_tail: ?*const u8 = null;

    if (db == null) {
        return NotesDbError.InvalidDatabase;
    }
    try check_rc(db, dbapi.sqlite3_prepare_v2(db, sql_find_all, sql_find_all.len, &stmt, &sql_tail), dbapi.SQLITE_OK);

    var irows: i32 = 0;
    var step_rc: i32 = dbapi.sqlite3_step(stmt);

    while (step_rc == dbapi.SQLITE_ROW) : (step_rc = dbapi.sqlite3_step(stmt)) {
        irows += 1;
        try records.append(std.ArrayList(u8).init(test_alloc));
        var record_buffer = records.getLast();

        //ACTIVE -- initialize buffer writer

        // var record = std.ArrayList(u8).init(test_alloc);
        // var record_buffer = std.ArrayList(u8).init(test_alloc);
        // defer record_buffer.deinit();  // TODO: deallocate later
        var id: ?i32 = null;
        var note: ?[]const u8 = null;
        defer if (note) |_note| test_alloc.free(_note);

        const col_count: i32 = dbapi.sqlite3_column_count(stmt);
        if (col_count != 2) {
            return NotesDbError.InvalidSchema;
        }
        var cidx: u2 = 0; // Only 2 columns
        while (cidx < col_count) : (cidx += 1) {
            const ctype: i32 = dbapi.sqlite3_column_type(stmt, cidx);
            switch (cidx) {
                @intFromEnum(NotesColumns.recordId) => try handleInt(ctype, cidx, stmt, &id),
                @intFromEnum(NotesColumns.note) => try handleText(test_alloc, ctype, cidx, stmt, &note),
                else => return NotesDbError.InvalidDataType,
            }
        }
        try record_buffer.writer().print("Record: {d}, {s}\n", .{ id.?, note.? });
        try records.append(record_buffer);
    }
    try check_rc(db, step_rc, dbapi.SQLITE_DONE);
    try check_rc(db, dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
    // return records;

    try stdout.print("(D): RECORDS ({d}):\n", .{records.items.len});
    for (records.items) |record| {
        try stdout.print("  {s}", .{record.items});
    }
}

pub fn insert(db: ?*dbapi.sqlite3) !void {
    var stmt: ?*dbapi.sqlite3_stmt = null;
    var sql_tail: ?*const u8 = null;

    var sql_buffer = std.ArrayList(u8).init(test_alloc);
    try sql_buffer.writer().print(sql_insert, .{ 1, "SAMPLE TEXT" });
    defer sql_buffer.deinit();
    const sql_z = try test_alloc.dupeZ(u8, sql_buffer.items);
    defer test_alloc.free(sql_z);

    try check_rc(db, dbapi.sqlite3_prepare_v2(db, sql_z, @intCast(sql_z.len), &stmt, &sql_tail), dbapi.SQLITE_OK);

    // try check_rc(db, dbapi.sqlite3_open(fname, db), dbapi.SQLITE_OK);
    // try check_rc(db, dbapi.sqlite3_prepare_v2(db, sql_insert, sql_insert.len, &stmt, &sql_tail), dbapi.SQLITE_OK);
    try check_rc(db, dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
    try check_rc(db, dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
}

pub fn insert_params(db: ?*dbapi.sqlite3) !void {
    var stmt: ?*dbapi.sqlite3_stmt = null;
    var sql_tail: ?*const u8 = null;

    const str_param = "RECORD WITH PARAM 'with' quotes";

    try check_rc(db, dbapi.sqlite3_prepare_v2(db, sql_insert_params, @intCast(sql_insert_params.len), &stmt, &sql_tail), dbapi.SQLITE_OK);

    try check_rc(db, dbapi.sqlite3_bind_int(
        stmt,
        1,
        12,
    ), dbapi.SQLITE_OK);

    try check_rc(db, dbapi.sqlite3_bind_text(
        stmt,
        2,
        str_param,
        str_param.len,
        dbapi.SQLITE_STATIC,
    ), dbapi.SQLITE_OK);

    const sql_z = dbapi.sqlite3_sql(stmt);
    const sql_bind_z = dbapi.sqlite3_expanded_sql(stmt);
    defer dbapi.sqlite3_free(sql_bind_z);

    try stdout.print("(D): SQL:      {s}\n     BIND SQL: {s}\n", .{ sql_z, sql_bind_z });

    try check_rc(db, dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
    try check_rc(db, dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
}

pub fn search_params(db: ?*dbapi.sqlite3) !void {
    var stmt: ?*dbapi.sqlite3_stmt = null;
    var sql_tail: ?*const u8 = null;

    if (db == null) {
        return NotesDbError.InvalidDatabase;
    }

    const str_param = "'";
    var str_buffer = std.ArrayList(u8).init(test_alloc);
    defer str_buffer.deinit();
    try str_buffer.writer().print("%{s}%", .{str_param});
    const str_z = try test_alloc.dupeZ(u8, str_buffer.items);
    defer test_alloc.free(str_z);

    try check_rc(db, dbapi.sqlite3_prepare_v2(
        db,
        sql_search_params,
        @intCast(sql_search_params.len),
        &stmt,
        &sql_tail,
    ), dbapi.SQLITE_OK);

    try check_rc(db, dbapi.sqlite3_bind_text(
        stmt,
        1,
        str_z,
        @intCast(str_z.len),
        dbapi.SQLITE_STATIC,
    ), dbapi.SQLITE_OK);

    const sql_z = dbapi.sqlite3_sql(stmt);
    const sql_bind_z = dbapi.sqlite3_expanded_sql(stmt);
    defer dbapi.sqlite3_free(sql_bind_z);
    try stdout.print("(D): SQL:      {s}\n     BIND SQL: {s}\n", .{ sql_z, sql_bind_z });

    var records = std.ArrayList(std.ArrayList(u8)).init(test_alloc);
    defer {
        for (records.items) |item| {
            item.deinit();
        }
        records.deinit();
    }

    var irows: i32 = 0;
    var step_rc: i32 = dbapi.sqlite3_step(stmt);

    while (step_rc == dbapi.SQLITE_ROW) : (step_rc = dbapi.sqlite3_step(stmt)) {
        irows += 1;
        try records.append(std.ArrayList(u8).init(test_alloc));
        var record_buffer = records.getLast();

        //ACTIVE -- initialize buffer writer

        // var record = std.ArrayList(u8).init(test_alloc);
        // var record_buffer = std.ArrayList(u8).init(test_alloc);
        // defer record_buffer.deinit();  // TODO: deallocate later
        var id: ?i32 = null;
        var note: ?[]const u8 = null;
        defer if (note) |_note| test_alloc.free(_note);

        const col_count: i32 = dbapi.sqlite3_column_count(stmt);
        if (col_count != 2) {
            return NotesDbError.InvalidSchema;
        }
        var cidx: u2 = 0; // Only 2 columns
        while (cidx < col_count) : (cidx += 1) {
            const ctype: i32 = dbapi.sqlite3_column_type(stmt, cidx);
            switch (cidx) {
                @intFromEnum(NotesColumns.recordId) => try handleInt(ctype, cidx, stmt, &id),
                @intFromEnum(NotesColumns.note) => try handleText(test_alloc, ctype, cidx, stmt, &note),
                else => return NotesDbError.InvalidDataType,
            }
        }
        try record_buffer.writer().print("Record: {d}, {s}\n", .{ id.?, note.? });
        try records.append(record_buffer);
    }
    try check_rc(db, step_rc, dbapi.SQLITE_DONE);
    try check_rc(db, dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
    // return records;

    try stdout.print("(D): RECORDS ({d}):\n", .{records.items.len});
    for (records.items) |record| {
        try stdout.print("  {s}", .{record.items});
    }
}

pub fn delete_all_notes(db: ?*dbapi.sqlite3) !void {
    // FIXME: This is a misnomer. It actually drops the notes table from the database
    var stmt: ?*dbapi.sqlite3_stmt = null;
    var sql_tail: ?*const u8 = null;

    if (db == null) {
        return NotesDbError.InvalidDatabase;
    }
    try check_rc(db, dbapi.sqlite3_prepare_v2(db, sql_delete_all_notes, sql_delete_all_notes.len, &stmt, &sql_tail), dbapi.SQLITE_OK);
    try check_rc(db, dbapi.sqlite3_step(stmt), dbapi.SQLITE_DONE);
    try check_rc(db, dbapi.sqlite3_finalize(stmt), dbapi.SQLITE_OK);
}

test "create database" {
    const expect = std.testing.expect;
    // const test_alloc = std.testing.allocator;
    // const eql = std.mem.eql;
    // const fname = "./tmp_test/test_create_1.db";
    _ = expect;
    // _ = test_alloc;

    var db: ?*dbapi.sqlite3 = null;

    try open_or_create_db(&db);
    try delete_all_notes(db);
    try close_db(db);
    try open_or_create_db(&db);
    db = null;
}

test "insert record" {
    // const expect = std.testing.expect;
    // const eql = std.mem.eql;
    // const fname = "./tmp_test/test_create.db";

    var db: ?*dbapi.sqlite3 = null;

    try open_or_create_db(&db);
    try delete_all_notes(db);
    try open_or_create_db(&db);
    try insert(db);

    db = null;
}

test "insert record params" {
    // const expect = std.testing.expect;
    // const eql = std.mem.eql;
    // const fname = "./tmp_test/test_create.db";

    var db: ?*dbapi.sqlite3 = null;

    try open_or_create_db(&db);
    try insert_params(db);
    try all_notes(db);

    db = null;
}

test "search record params" {
    // const expect = std.testing.expect;
    // const eql = std.mem.eql;
    // const fname = "./tmp_test/test_create.db";

    var db: ?*dbapi.sqlite3 = null;

    try stdout.writeAll("\n(T): ---- SEARCH RECORD PARAMS ----\n");
    try open_or_create_db(&db);
    try delete_all_notes(db);
    try open_or_create_db(&db);
    try insert_params(db);
    try insert(db);
    try search_params(db);

    db = null;
}
