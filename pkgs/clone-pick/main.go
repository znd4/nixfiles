// clone-pick picks a repository (from GitHub, a GitLab host, or a pasted URL),
// clones it into <work-dir>/<host>/<path> unless it is already there, and opens
// it as a sesh session or a herdr workspace.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/huh/spinner"
	"github.com/charmbracelet/lipgloss"
)

type listFlag []string

func (l *listFlag) String() string     { return strings.Join(*l, ",") }
func (l *listFlag) Set(v string) error { *l = append(*l, v); return nil }

type repo struct {
	name   string // owner/repo, shown in the picker
	remote string // what gets cloned
}

const (
	sourceGitHub = "github"
	sourceURL    = "url"
)

func main() {
	var gitlabHosts, githubOrgs listFlag
	flag.Var(&gitlabHosts, "gitlab-host", "GitLab host to offer as a source (repeatable)")
	flag.Var(&githubOrgs, "github-org", "GitHub org whose repos are listed besides your own (repeatable)")
	workDir := flag.String("work-dir", defaultWorkDir(), "clone root; repos land in <work-dir>/<host>/<path>")
	open := flag.String("open", "print", "what to do with the checkout: sesh, herdr or print")
	waitOnError := flag.Bool("wait-on-error", false, "on failure, wait for enter before exiting (for popups)")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "usage: clone-pick [flags] [remote]\n\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	err := run(context.Background(), *workDir, *open, gitlabHosts, githubOrgs, flag.Arg(0))
	if errors.Is(err, huh.ErrUserAborted) {
		return
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "clone-pick:", err)
		if *waitOnError {
			fmt.Fprint(os.Stderr, "press enter to close")
			_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
		}
		os.Exit(1)
	}
}

func defaultWorkDir() string {
	if d := os.Getenv("CLONE_PICK_WORK_DIR"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Work")
}

func run(ctx context.Context, workDir, open string, gitlabHosts, githubOrgs []string, remote string) error {
	if !slices.Contains([]string{"sesh", "herdr", "print"}, open) {
		return fmt.Errorf("--open must be sesh, herdr or print, not %q", open)
	}
	if remote == "" {
		var err error
		if remote, err = pick(ctx, workDir, gitlabHosts, githubOrgs); err != nil {
			return err
		}
	}

	dir, err := RepoDir(workDir, remote)
	if err != nil {
		return err
	}
	if _, err := os.Stat(dir); errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
			return err
		}
		fmt.Fprintf(os.Stderr, "cloning %s into %s\n", remote, dir)
		if err := runAttached(ctx, "git", "clone", remote, dir); err != nil {
			return fmt.Errorf("git clone %s: %w", remote, err)
		}
	} else if err != nil {
		return err
	}

	switch open {
	case "sesh":
		return runAttached(ctx, "sesh", "connect", dir)
	case "herdr":
		return runAttached(ctx, "herdr", "workspace", "create", "--cwd", dir, "--label", filepath.Base(dir), "--focus")
	default:
		fmt.Println(dir)
		return nil
	}
}

func pick(ctx context.Context, workDir string, gitlabHosts, githubOrgs []string) (string, error) {
	sources := []huh.Option[string]{huh.NewOption("GitHub", sourceGitHub)}
	for _, h := range gitlabHosts {
		sources = append(sources, huh.NewOption("GitLab: "+h, h))
	}
	sources = append(sources, huh.NewOption("Paste a URL", sourceURL))

	var source string
	if err := huh.NewSelect[string]().
		Title("Clone from where?").
		Options(sources...).
		Value(&source).
		Run(); err != nil {
		return "", err
	}

	if source == sourceURL {
		var remote string
		err := huh.NewInput().
			Title("Git remote").
			Placeholder("git@host:owner/repo.git or https://host/owner/repo").
			Validate(func(s string) error { _, _, err := ParseRemote(s); return err }).
			Value(&remote).
			Run()
		return strings.TrimSpace(remote), err
	}

	var repos []repo
	var listErr error
	title := "Listing GitHub repos…"
	if source != sourceGitHub {
		title = "Listing " + source + " repos…"
	}
	if err := spinner.New().Title(title).Context(ctx).Action(func() {
		if source == sourceGitHub {
			repos, listErr = listGitHub(ctx, githubOrgs)
		} else {
			repos, listErr = listGitLab(ctx, source)
		}
	}).Run(); err != nil {
		return "", err
	}
	if listErr != nil {
		return "", listErr
	}
	if len(repos) == 0 {
		return "", errors.New("no repos found")
	}

	cloned := lipgloss.NewStyle().Faint(true).Render(" (cloned)")
	options := make([]huh.Option[string], 0, len(repos))
	for _, r := range repos {
		label := r.name
		if dir, err := RepoDir(workDir, r.remote); err == nil {
			if _, err := os.Stat(dir); err == nil {
				label += cloned
			}
		}
		options = append(options, huh.NewOption(label, r.remote))
	}

	var remote string
	err := huh.NewSelect[string]().
		Title("Repo").
		Options(options...).
		Filtering(true).
		Height(20).
		Value(&remote).
		Run()
	return remote, err
}

// listGitHub lists your own repos plus those of each org, in parallel.
func listGitHub(ctx context.Context, orgs []string) ([]repo, error) {
	owners := append([]string{""}, orgs...)
	results := make([][]string, len(owners))
	errs := make([]error, len(owners))
	var wg sync.WaitGroup
	for i, owner := range owners {
		wg.Add(1)
		go func() {
			defer wg.Done()
			args := []string{"repo", "list"}
			if owner != "" {
				args = append(args, owner)
			}
			args = append(args, "--json", "nameWithOwner", "--jq", ".[].nameWithOwner", "--limit", "100000")
			out, err := output(ctx, nil, "gh", args...)
			results[i], errs[i] = strings.Fields(out), err
		}()
	}
	wg.Wait()
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}

	names := slices.Concat(results...)
	slices.Sort(names)
	names = slices.Compact(names)
	repos := make([]repo, len(names))
	for i, n := range names {
		repos[i] = repo{name: n, remote: "git@github.com:" + n + ".git"}
	}
	return repos, nil
}

func listGitLab(ctx context.Context, host string) ([]repo, error) {
	out, err := output(ctx, []string{"GITLAB_HOST=" + host}, "glab", "repo", "list", "--output", "json", "-P", "1000")
	if err != nil {
		return nil, err
	}
	var projects []struct {
		PathWithNamespace string `json:"path_with_namespace"`
		SSHURLToRepo      string `json:"ssh_url_to_repo"`
	}
	if err := json.Unmarshal([]byte(out), &projects); err != nil {
		return nil, fmt.Errorf("parse glab output: %w", err)
	}
	repos := make([]repo, 0, len(projects))
	for _, p := range projects {
		remote := p.SSHURLToRepo
		if remote == "" {
			remote = "git@" + host + ":" + p.PathWithNamespace + ".git"
		}
		repos = append(repos, repo{name: p.PathWithNamespace, remote: remote})
	}
	slices.SortFunc(repos, func(a, b repo) int { return strings.Compare(a.name, b.name) })
	return repos, nil
}

func output(ctx context.Context, env []string, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Env = append(os.Environ(), env...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return string(out), nil
}

func runAttached(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stderr, os.Stderr
	return cmd.Run()
}
