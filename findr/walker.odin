package findr

import "core:bytes"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sync/chan"
import "core:sys/linux"
import "core:text/regex"
import "core:thread"

OUTPUT_BUF_SIZE :: 64 * 1024

WalkOptions :: struct {
	pattern:  string, // regex on basename; "" = match all
	excludes: []string, // glob patterns to skip entirely
}

GIContext :: struct {
	gi:       ^Gitignore, // nil if this dir had no .gitignore
	base_rel: string, // relative path from repo root to this dir
	parent:   ^GIContext, // parent context (nil if repo root)
}

WorkItem :: struct {
	path:       string, // absolute directory path
	rel:        string, // relative path from repo root ("" = root)
	gi_ctx:     ^GIContext, // gitignore chain (nil = outside any repo)
	in_repo:    bool, // true if inside a git repo
	in_ignored: bool, // true if inside a gitignored directory
}

WalkerPool :: struct {
	queue:         [dynamic]WorkItem,
	queue_mutex:   sync.Mutex,
	queue_sema:    sync.Atomic_Sema,
	result_chan:   chan.Chan([]u8),
	active:        i64,
	done:          sync.One_Shot_Event,
	threads:       []^thread.Thread,
	opts:          WalkOptions,
	pattern_re:    regex.Regular_Expression,
	has_pattern:   bool,
	exclude_gi:    ^Gitignore,
	all_contexts:  [dynamic]^GIContext,
	contexts_lock: sync.Mutex,
}

Collector_Data :: struct {
	ch:      chan.Chan([]u8),
	results: ^[dynamic]string,
}

collect_worker :: proc(t: ^thread.Thread) {
	data := cast(^Collector_Data)t.data
	for {
		batch := chan.recv(data.ch) or_break
		defer delete(batch)

		start := 0
		for {
			remaining: []u8
			#no_bounds_check {remaining = batch[start:]}

			idx := bytes.index_byte(remaining, '\n')
			if idx < 0 do break

			i := start + idx
			if i > start {
				segment: []u8
				#no_bounds_check {segment = batch[start:i]}
				s, _ := strings.clone(string(segment))
				append(data.results, s)
			}
			start = i + 1
		}
	}
}

walk :: proc(roots: []string, results: ^[dynamic]string, opts: WalkOptions, thread_count: int) {
	if len(roots) == 0 do return

	ch, _ := chan.create(chan.Chan([]u8), max(2 * thread_count, 2), context.allocator)
	defer chan.destroy(ch)

	data := new(Collector_Data)
	data.ch = ch
	data.results = results
	defer free(data)

	collector := thread.create(collect_worker)
	collector.data = rawptr(data)
	collector.init_context = context
	thread.start(collector)

	pool := new(WalkerPool)
	pool.queue = make([dynamic]WorkItem)
	pool.result_chan = ch
	pool.active = i64(len(roots))
	pool.threads = make([]^thread.Thread, thread_count)
	pool.all_contexts = make([dynamic]^GIContext)
	pool.opts = opts
	pool.exclude_gi = nil
	pool.has_pattern = false

	if len(opts.pattern) > 0 {
		re, err := regex.create(opts.pattern, {regex.Flag.No_Capture})
		if err == nil {
			pool.pattern_re = re
			pool.has_pattern = true
		}
	}

	if len(opts.excludes) > 0 {
		sb: strings.Builder
		strings.builder_init(&sb)
		for ex in opts.excludes {
			fmt.sbprintf(&sb, "%s\n", ex)
		}
		content := strings.to_string(sb)
		pool.exclude_gi = new(Gitignore)
		pool.exclude_gi^ = parse(content)
		strings.builder_destroy(&sb)
	}

	for root in roots {
		root_clone, _ := strings.clone(root)
		append(&pool.queue, WorkItem{path = root_clone})
		sync.atomic_sema_post(&pool.queue_sema)
	}

	for i in 0 ..< thread_count {
		t := thread.create(walk_worker)
		t.data = rawptr(pool)
		t.init_context = context
		thread.start(t)
		pool.threads[i] = t
	}

	sync.one_shot_event_wait(&pool.done)

	for _ in 0 ..< thread_count {
		sync.atomic_sema_post(&pool.queue_sema)
	}

	for t in pool.threads {
		thread.destroy(t)
	}
	delete(pool.threads)
	for item in pool.queue {
		delete(item.path)
		if len(item.rel) > 0 {delete(item.rel)}
	}
	delete(pool.queue)

	for ctx in pool.all_contexts {
		if ctx.gi != nil {
			destroy(ctx.gi)
			free(ctx.gi)
		}
		if len(ctx.base_rel) > 0 {
			delete(ctx.base_rel)
		}
		free(ctx)
	}
	delete(pool.all_contexts)

	if pool.has_pattern {
		regex.destroy(pool.pattern_re)
	}
	if pool.exclude_gi != nil {
		destroy(pool.exclude_gi)
		free(pool.exclude_gi)
	}

	free(pool)

	chan.close(ch)
	thread.join(collector)
	thread.destroy(collector)
}

flush_buf :: proc(ch: chan.Chan([]u8), local: ^[dynamic]u8) {
	if len(local) == 0 do return
	batch := local[:]
	local^ = make([dynamic]u8, 0, OUTPUT_BUF_SIZE)
	chan.send(ch, batch)
}

append_path :: proc(buf: ^[dynamic]u8, parent, name: string, trailing_slash: bool) {
	need_sep := len(parent) > 0 && parent[len(parent) - 1] != '/'
	size := len(parent) + len(name) + 1
	if need_sep do size += 1
	if trailing_slash do size += 1

	old_len := len(buf)
	reserve(buf, old_len + size)
	resize(buf, old_len + size)

	pos := old_len
	pos += copy(buf[pos:], parent)
	if need_sep {buf[pos] = '/'; pos += 1}
	pos += copy(buf[pos:], name)
	if trailing_slash {buf[pos] = '/'; pos += 1}
	buf[pos] = '\n'
}

walk_worker :: proc(t: ^thread.Thread) {
	pool := cast(^WalkerPool)t.data

	local_buf := make([dynamic]u8, 0, OUTPUT_BUF_SIZE)
	defer {
		if len(local_buf) > 0 {
			flush_buf(pool.result_chan, &local_buf)
		}
		delete(local_buf)
	}

	for {
		sync.atomic_sema_wait(&pool.queue_sema)

		sync.mutex_lock(&pool.queue_mutex)
		if len(pool.queue) == 0 {
			sync.mutex_unlock(&pool.queue_mutex)
			if sync.atomic_load_explicit(&pool.active, .Acquire) == 0 {
				sync.one_shot_event_signal(&pool.done)
			}
			break
		}
		last := len(pool.queue) - 1
		item := pool.queue[last]
		ordered_remove(&pool.queue, last)
		sync.mutex_unlock(&pool.queue_mutex)

		process_dir(pool, item, &local_buf)
		delete(item.path)
		if len(item.rel) > 0 {delete(item.rel)}

		if len(local_buf) >= OUTPUT_BUF_SIZE {
			flush_buf(pool.result_chan, &local_buf)
		}

		old := sync.atomic_sub_explicit(&pool.active, 1, .Release)
		if old == 1 {
			sync.one_shot_event_signal(&pool.done)
		}
	}
}

process_dir :: proc(pool: ^WalkerPool, item: WorkItem, local_buf: ^[dynamic]u8) {
	dir_path := item.path

	cpath := strings.clone_to_cstring(dir_path)
	if cpath == nil do return
	defer delete(cpath)

	fd, open_err := linux.open(cpath, {.DIRECTORY, .CLOEXEC})
	if open_err != .NONE do return
	defer linux.close(fd)

	has_git := false
	if !item.in_ignored {
		has_git = has_git_dir(fd)
	}

	gi_ctx := item.gi_ctx
	rel := item.rel

	if has_git {
		gi_ctx = nil
		rel = ""
	}

	child_in_repo := has_git || item.in_repo

	gi: ^Gitignore = nil
	if !item.in_ignored {
		gi = load_ignore_patterns(dir_path, child_in_repo)
	}
	if gi != nil {
		new_ctx := new(GIContext)
		new_ctx.gi = gi
		if len(rel) > 0 {
			new_ctx.base_rel, _ = strings.clone(rel)
		}
		new_ctx.parent = gi_ctx

		sync.mutex_lock(&pool.contexts_lock)
		append(&pool.all_contexts, new_ctx)
		sync.mutex_unlock(&pool.contexts_lock)

		gi_ctx = new_ctx
	}

	buf: [32 * 1024]u8
	rel_buf: [4096]u8

	for {
		n, errno := linux.getdents(fd, buf[:])
		if n <= 0 || errno != .NONE do break

		offs := 0
		for d in linux.dirent_iterate_buf(buf[:n], &offs) {
			name := linux.dirent_name(d)
			if name == "." || name == ".." do continue
			if name == ".git" do continue

			is_dir := d.type == .DIR
			is_nondir := d.type != .DIR

			if pool.exclude_gi != nil && is_ignored(pool.exclude_gi, name, is_dir) {
				continue
			}

			entry_rel := build_rel(rel_buf[:], rel, name)

			ignored := false
			if item.in_ignored {
				ignored = true
			} else if gi_ctx != nil {
				ignored = check_chain(gi_ctx, entry_rel, is_dir)
			}

			if is_dir {
				if ignored && matches_pattern(pool, name) {
					append_path(local_buf, dir_path, name, true)
				}
				child_rel, _ := strings.clone(entry_rel)
				child_path := join_path(dir_path, name)
				push_work(
					pool,
					WorkItem {
						path = child_path,
						rel = child_rel,
						gi_ctx = gi_ctx,
						in_repo = child_in_repo,
						in_ignored = ignored,
					},
				)
			} else if is_nondir {
				if ignored && matches_pattern(pool, name) {
					append_path(local_buf, dir_path, name, false)
				}
			}
		}
	}
}

check_chain :: proc(ctx: ^GIContext, entry_rel: string, is_dir: bool) -> bool {
	c := ctx
	for c != nil {
		if c.gi != nil {
			rel := relative_to(entry_rel, c.base_rel)
			match := check_match(c.gi, rel, is_dir)
			if match != .None {
				return match == .Ignored
			}
		}
		c = c.parent
	}
	return false
}

relative_to :: proc(entry_rel, base_rel: string) -> string {
	if len(base_rel) == 0 do return entry_rel
	prefix_len := len(base_rel)
	if len(entry_rel) > prefix_len &&
	   entry_rel[prefix_len] == '/' &&
	   strings.has_prefix(entry_rel, base_rel) {
		return entry_rel[prefix_len + 1:]
	}
	return entry_rel
}

build_rel :: proc(buf: []u8, rel, name: string) -> string {
	if len(rel) == 0 do return name
	pos := copy(buf, rel)
	if pos < len(buf) {
		buf[pos] = '/'
		pos += 1
		pos += copy(buf[pos:], name)
	}
	return string(buf[:pos])
}

matches_pattern :: proc(pool: ^WalkerPool, name: string) -> bool {
	if !pool.has_pattern do return true
	cap, ok := regex.match(pool.pattern_re, name)
	regex.destroy(cap)
	return ok
}

push_work :: proc(pool: ^WalkerPool, item: WorkItem) {
	sync.atomic_add_explicit(&pool.active, 1, .Relaxed)
	sync.mutex_lock(&pool.queue_mutex)
	append(&pool.queue, item)
	sync.mutex_unlock(&pool.queue_mutex)
	sync.atomic_sema_post(&pool.queue_sema)
}

has_git_dir :: proc(fd: linux.Fd) -> bool {
	git_fd, err := linux.openat(fd, ".git", {.DIRECTORY, .CLOEXEC})
	if err == .NONE {
		linux.close(git_fd)
		return true
	}
	return false
}

load_ignore_patterns :: proc(dir_path: string, in_repo: bool) -> ^Gitignore {
	has_patterns := false
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	if in_repo {
		gi_path := join_path(dir_path, ".gitignore")
		data, err := os.read_entire_file_from_path(gi_path, context.allocator)
		delete(gi_path)
		if err == .NONE {
			fmt.sbprintf(&sb, "%s", string(data))
			delete(data)
			has_patterns = true
		}
	}

	ig_path := join_path(dir_path, ".ignore")
	idata, ierr := os.read_entire_file_from_path(ig_path, context.allocator)
	delete(ig_path)
	if ierr == .NONE {
		fmt.sbprintf(&sb, "%s", string(idata))
		delete(idata)
		has_patterns = true
	}

	if !has_patterns do return nil

	content := strings.to_string(sb)
	gi := new(Gitignore)
	gi^ = parse(content)
	return gi
}

join_path :: proc(parent, child: string) -> string {
	need_sep := len(parent) == 0 || parent[len(parent) - 1] != '/'
	total := len(parent) + len(child)
	if need_sep do total += 1
	buf := make([]u8, total, context.allocator)
	pos := copy(buf, parent)
	if need_sep {
		buf[pos] = '/'
		pos += 1
	}
	copy(buf[pos:], child)
	return string(buf)
}

