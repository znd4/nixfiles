package main

import (
	"fmt"
	"net/url"
	"path/filepath"
	"strings"
)

// ParseRemote splits a git remote into its host and repository path:
//
//	git@github.com:owner/repo.git         -> github.com, owner/repo
//	https://gitlab.example.com/a/b/c.git  -> gitlab.example.com, a/b/c
//	ssh://git@host:2222/a/b.git           -> host, a/b
//	github.com/owner/repo                 -> github.com, owner/repo
func ParseRemote(remote string) (host, path string, err error) {
	remote = strings.TrimSpace(remote)
	switch {
	case strings.Contains(remote, "://"):
		u, perr := url.Parse(remote)
		if perr != nil {
			return "", "", fmt.Errorf("parse remote %q: %w", remote, perr)
		}
		host, path = u.Hostname(), u.Path
	default:
		// scp-like `[user@]host:path`, or a bare `host/path`.
		hostPart, rest, ok := strings.Cut(remote, ":")
		if !ok || strings.Contains(hostPart, "/") {
			hostPart, rest, _ = strings.Cut(remote, "/")
		}
		if _, after, found := strings.Cut(hostPart, "@"); found {
			hostPart = after
		}
		host, path = hostPart, rest
	}

	path = strings.TrimSuffix(strings.Trim(path, "/"), ".git")
	if host == "" || path == "" {
		return "", "", fmt.Errorf("no host/path in remote %q", remote)
	}
	segs := strings.Split(path, "/")
	if len(segs) < 2 {
		return "", "", fmt.Errorf("want <owner>/<repo>, got %q in remote %q", path, remote)
	}
	for _, seg := range segs {
		if seg == "" || seg == "." || seg == ".." {
			return "", "", fmt.Errorf("bad path %q in remote %q", path, remote)
		}
	}
	return strings.ToLower(host), path, nil
}

// RepoDir is where remote lives under workDir: <workDir>/<host>/<path>.
func RepoDir(workDir, remote string) (string, error) {
	host, path, err := ParseRemote(remote)
	if err != nil {
		return "", err
	}
	return filepath.Join(workDir, host, filepath.FromSlash(path)), nil
}
