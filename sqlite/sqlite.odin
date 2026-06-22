package sqlite

import "core:c"

foreign import lib "system:sqlite3"

Db :: distinct rawptr
Stmt :: distinct rawptr

// TODO: Use an enum?
OK :: 0
ROW :: 100
DONE :: 101


DESERIALIZE_FLAGS :: bit_set[DESERIALIZE_FLAG]
DESERIALIZE_FLAG :: enum u32 {
	FREEONCLOSE = 1,
	RESIZEABLE  = 2,
}

foreign lib {
	@(link_name = "sqlite3_open")
	open :: proc(filename: cstring, ppDb: ^Db) -> c.int ---
	@(link_name = "sqlite3_close")
	close :: proc(db: Db) -> c.int ---
	@(link_name = "sqlite3_errmsg")
	errmsg :: proc(db: Db) -> cstring ---
	@(link_name = "sqlite3_exec")
	exec :: proc(db: Db, sql: cstring, callback: rawptr, callback_arg: rawptr, errmsg: ^cstring) -> c.int ---
	@(link_name = "sqlite3_prepare_v2")
	prepare_v2 :: proc(db: Db, sql: cstring, nByte: c.int, ppStmt: ^Stmt, pzTail: ^cstring) -> c.int ---
	@(link_name = "sqlite3_step")
	step :: proc(stmt: Stmt) -> c.int ---
	@(link_name = "sqlite3_finalize")
	finalize :: proc(stmt: Stmt) -> c.int ---
	@(link_name = "sqlite3_column_text")
	column_text :: proc(stmt: Stmt, iCol: c.int) -> cstring ---
	@(link_name = "sqlite3_column_bytes")
	column_bytes :: proc(stmt: Stmt, iCol: c.int) -> c.int ---
	@(link_name = "sqlite3_bind_text")
	bind_text :: proc(stmt: Stmt, idx: c.int, val: cstring, n: c.int, destructor: rawptr) -> c.int ---
	@(link_name = "sqlite3_changes")
	changes :: proc(db: Db) -> c.int ---
	@(link_name = "sqlite3_serialize")
	serialize :: proc(db: Db, zSchema: cstring, piSize: ^i64, mFlags: u32) -> [^]u8 ---
	@(link_name = "sqlite3_deserialize")
	deserialize :: proc(db: Db, zSchema: cstring, pData: [^]u8, szDb: i64, szBuf: i64, mFlags: DESERIALIZE_FLAGS) -> c.int ---
	@(link_name = "sqlite3_malloc64")
	malloc64 :: proc(n: i64) -> [^]u8 ---
	@(link_name = "sqlite3_free")
	free :: proc(p: rawptr) ---
}

