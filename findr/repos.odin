package findr

import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:thread"

RepoPool :: struct {
	queue:        [dynamic]string,
	queue_mutex:  sync.Mutex,
	queue_sema:   sync.Atomic_Sema,
	results:      ^[dynamic]string,
	results_lock: sync.Mutex,
	active:       i64,
	done:         sync.One_Shot_Event,
	threads:      []^thread.Thread,
}

find_repos :: proc(
	roots: []string,
	results: ^[dynamic]string,
	thread_count: int,
	allocator := context.allocator,
) {
	// TODO: This may be a code smell
	context.allocator = allocator
	if len(roots) == 0 do return

	pool := new(RepoPool)
	pool.queue = make([dynamic]string)
	pool.results = results
	pool.active = i64(len(roots))
	pool.threads = make([]^thread.Thread, thread_count)

	for root in roots {
		root_clone := strings.clone(root)
		append(&pool.queue, root_clone)
		sync.atomic_sema_post(&pool.queue_sema)
	}

	for i in 0 ..< thread_count {
		t := thread.create(repo_worker)
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

	for path in pool.queue {
		delete(path)
	}
	delete(pool.queue)

	free(pool)
}

repo_worker :: proc(t: ^thread.Thread) {
	pool := cast(^RepoPool)t.data

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
		dir_path := pool.queue[last]
		ordered_remove(&pool.queue, last)
		sync.mutex_unlock(&pool.queue_mutex)

		process_repo_dir(pool, dir_path)
		delete(dir_path)

		old := sync.atomic_sub_explicit(&pool.active, 1, .Release)
		if old == 1 {
			sync.one_shot_event_signal(&pool.done)
		}
	}
}

process_repo_dir :: proc(pool: ^RepoPool, dir_path: string) {
	cpath := strings.clone_to_cstring(dir_path)
	if cpath == nil do return
	defer delete(cpath)

	fd, open_err := linux.open(cpath, {.DIRECTORY, .CLOEXEC})
	if open_err != .NONE do return
	defer linux.close(fd)

	if has_git_dir(fd) {
		cloned := strings.clone(dir_path)
		sync.mutex_lock(&pool.results_lock)
		append(pool.results, cloned)
		sync.mutex_unlock(&pool.results_lock)
	}

	buf: [32 * 1024]u8

	for {
		n, errno := linux.getdents(fd, buf[:])
		if n <= 0 || errno != .NONE do break

		offs := 0
		for d in linux.dirent_iterate_buf(buf[:n], &offs) {
			name := linux.dirent_name(d)
			if name == "." || name == ".." do continue
			if name == ".git" do continue

			if d.type == .DIR {
				child_path := join_path(dir_path, name)
				sync.atomic_add_explicit(&pool.active, 1, .Relaxed)
				sync.mutex_lock(&pool.queue_mutex)
				append(&pool.queue, child_path)
				sync.mutex_unlock(&pool.queue_mutex)
				sync.atomic_sema_post(&pool.queue_sema)
			}
		}
	}
}

