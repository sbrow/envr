package main

import "core:testing"

@(test)
test_db_update_required_noop :: proc(t: ^testing.T) {
	testing.expect(t, !db_update_required(.Noop), "Noop should not require update")
}

@(test)
test_db_update_required_backed_up :: proc(t: ^testing.T) {
	testing.expect(t, db_update_required(.BackedUp), "BackedUp should require update")
}

@(test)
test_db_update_required_dir_updated :: proc(t: ^testing.T) {
	testing.expect(t, db_update_required(.DirUpdated), "DirUpdated should require update")
}

@(test)
test_db_update_required_restored :: proc(t: ^testing.T) {
	testing.expect(t, !db_update_required(.Restored), "Restored alone should not require update")
}

@(test)
test_db_update_required_error :: proc(t: ^testing.T) {
	testing.expect(t, !db_update_required(.Error), "Error alone should not require update")
}

@(test)
test_db_update_required_combined :: proc(t: ^testing.T) {
	s := i32(SyncResult.DirUpdated) | i32(SyncResult.Restored)
	combined := SyncResult(s)
	testing.expect(t, db_update_required(combined), "DirUpdated|Restored should require update")
}

@(test)
test_shares_remote_overlap :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 2, context.temp_allocator),
	}
	append(&f.Remotes, "git@github.com:user/repo.git")
	append(&f.Remotes, "git@gitlab.com:user/repo.git")

	remotes := []string{"git@github.com:user/repo.git"}
	testing.expect(t, shares_remote(&f, remotes), "should share remote")
}

@(test)
test_shares_remote_no_overlap :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 1, context.temp_allocator),
	}
	append(&f.Remotes, "git@github.com:user/repo.git")

	remotes := []string{"git@github.com:other/repo.git"}
	testing.expect(t, !shares_remote(&f, remotes), "should not share remote")
}

@(test)
test_shares_remote_empty_file_remotes :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 0, context.temp_allocator),
	}

	remotes := []string{"git@github.com:user/repo.git"}
	testing.expect(t, !shares_remote(&f, remotes), "empty file remotes should not share")
}

@(test)
test_shares_remote_empty_check_remotes :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 1, context.temp_allocator),
	}
	append(&f.Remotes, "git@github.com:user/repo.git")

	remotes: []string
	testing.expect(t, !shares_remote(&f, remotes), "empty check remotes should not share")
}

@(test)
test_shares_remote_both_empty :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 0),
	}

	remotes: []string
	testing.expect(t, !shares_remote(&f, remotes), "both empty should not share")
}

