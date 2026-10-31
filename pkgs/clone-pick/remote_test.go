package main

import "testing"

func TestParseRemote(t *testing.T) {
	cases := []struct{ in, host, path string }{
		{"git@github.com:ktowen/obsidian-neovim-view", "github.com", "ktowen/obsidian-neovim-view"},
		{"git@github.com:znd4/nixfiles.git", "github.com", "znd4/nixfiles"},
		{"https://github.com/ktowen/obsidian-neovim-view", "github.com", "ktowen/obsidian-neovim-view"},
		{"https://github.com/o/r.git/", "github.com", "o/r"},
		{"https://gitlab.example.com/group/sub/repo.git", "gitlab.example.com", "group/sub/repo"},
		{"ssh://git@host.x:2222/a/b.git", "host.x", "a/b"},
		{"github.com/owner/repo", "github.com", "owner/repo"},
		{"  git@GitLab.com:a/b/c.git\n", "gitlab.com", "a/b/c"},
	}
	for _, c := range cases {
		host, path, err := ParseRemote(c.in)
		if err != nil {
			t.Errorf("ParseRemote(%q): %v", c.in, err)
			continue
		}
		if host != c.host || path != c.path {
			t.Errorf("ParseRemote(%q) = %q, %q; want %q, %q", c.in, host, path, c.host, c.path)
		}
	}
}

func TestParseRemoteRejects(t *testing.T) {
	for _, in := range []string{"", "github.com", "git@github.com:", "https://github.com/", "git@h:a/../b", "https://h/a//b", "git@github.com:foo"} {
		if host, path, err := ParseRemote(in); err == nil {
			t.Errorf("ParseRemote(%q) = %q, %q; want error", in, host, path)
		}
	}
}

func TestRepoDir(t *testing.T) {
	got, err := RepoDir("/home/u/Work", "https://github.com/ktowen/obsidian-neovim-view")
	if err != nil {
		t.Fatal(err)
	}
	if want := "/home/u/Work/github.com/ktowen/obsidian-neovim-view"; got != want {
		t.Errorf("RepoDir = %q, want %q", got, want)
	}
}
