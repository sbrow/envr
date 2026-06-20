package sqlite

import "core:c"

foreign import lib "system:sqlite3"

OK :: 0
ROW :: 100
DONE :: 101

DESERIALIZE_FREEONCLOSE :: 1
DESERIALIZE_RESIZEABLE :: 2

foreign lib {
	@(link_name = "sqlite3_open")
	open :: proc(filename: cstring, ppDb: ^^rawptr) -> c.int ---
	@(link_name = "sqlite3_close")
	close :: proc(db: ^rawptr) -> c.int ---
	@(link_name = "sqlite3_errmsg")
	db_errmsg :: proc(db: ^rawptr) -> cstring ---
	@(link_name = "sqlite3_exec")
	db_exec :: proc(db: ^rawptr, sql: cstring, callback: rawptr, callback_arg: rawptr, errmsg: ^cstring) -> c.int ---
	@(link_name = "sqlite3_prepare_v2")
	prepare_v2 :: proc(db: ^rawptr, sql: cstring, nByte: c.int, ppStmt: ^^rawptr, pzTail: ^cstring) -> c.int ---
	@(link_name = "sqlite3_step")
	step :: proc(stmt: ^rawptr) -> c.int ---
	@(link_name = "sqlite3_finalize")
	finalize :: proc(stmt: ^rawptr) -> c.int ---
	@(link_name = "sqlite3_column_text")
	column_text :: proc(stmt: ^rawptr, iCol: c.int) -> cstring ---
	@(link_name = "sqlite3_column_bytes")
	column_bytes :: proc(stmt: ^rawptr, iCol: c.int) -> c.int ---
	@(link_name = "sqlite3_bind_text")
	bind_text :: proc(stmt: ^rawptr, idx: c.int, val: cstring, n: c.int, destructor: rawptr) -> c.int ---
	@(link_name = "sqlite3_changes")
	changes :: proc(db: ^rawptr) -> c.int ---
	@(link_name = "sqlite3_serialize")
	serialize :: proc(db: ^rawptr, zSchema: cstring, piSize: ^i64, mFlags: u32) -> [^]u8 ---
	@(link_name = "sqlite3_deserialize")
	deserialize :: proc(db: ^rawptr, zSchema: cstring, pData: [^]u8, szDb: i64, szBuf: i64, mFlags: u32) -> c.int ---
	@(link_name = "sqlite3_malloc64")
	malloc64 :: proc(n: i64) -> [^]u8 ---
	@(link_name = "sqlite3_free")
	free :: proc(p: rawptr) ---
}

