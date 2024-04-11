package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path"
	"syscall"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use: "sesh-new-project",
	Run: func(cmd *cobra.Command, args []string) {
		zCmd := exec.Command("zoxide", "query", "--list")
		zCmd.Start()

		outPipe, err := zCmd.StdoutPipe()
		if err != nil {
			log.Fatal(err)
		}
		pr, pw := io.Pipe()
		defer pr.Close()
		defer pw.Close()

		scanner := bufio.NewScanner(outPipe)
		go func() {
			for scanner.Scan() {
				line := scanner.Text()
				fileInfo, err := os.Stat(path.Join(line, ".git"))
				if err != nil || fileInfo.IsDir() {
					continue
				}
				pw.Write([]byte(line + "\n"))
			}
		}()
		promptCmd := exec.Command("fzf-tmux", "-p")
		promptCmd.Stdin = pr
		promptCmd.Start()
		pipe := "/tmp/sesh-new-project"
		if err := syscall.Mkfifo(pipe, 0600); err != nil {
			log.Fatal(err)
		}
		parentOut, err := promptCmd.Output()
		if err != nil {
			log.Fatal(err)
		}
		err = exec.Command("tmux", "popup", "-E", fmt.Sprintf("gum input --header 'What is the name of your new project?' > %s", pipe)).Run()
		if err != nil {
			log.Fatal(err)
		}
		projectName, err := os.ReadFile(pipe)
		if err != nil {
			log.Fatal(err)
		}
		os.Mkdir(
			path.Join(
				string(bytes.TrimSpace(parentOut)),
				string(bytes.TrimSpace(projectName)),
			),
			0755,
		)
	},
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
