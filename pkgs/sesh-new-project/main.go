package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path"
	"regexp"

	"github.com/spf13/cobra"
)

type Filter struct{}

var rootCmd = &cobra.Command{
	Use: "sesh-new-project",
	Run: func(cmd *cobra.Command, args []string) {
		outPipe, err := exec.Command("zoxide", "query", "--list").StdoutPipe()
		if err != nil {
			log.Fatal(err)
		}
		scanner := bufio.NewScanner(outPipe)
		candidates := []string{}
		for scanner.Scan() {
			line := scanner.Text()
			fileInfo, err := os.Stat(path.Join(line, ".git"))
			if err != nil || fileInfo.IsDir() {
				continue
			}
			candidates = append(candidates, line)
		}
		promptCmd := exec.Command("fzf-tmux", "-p")
		stdin, err := promptCmd.StdinPipe()
		if err != nil {
			log.Fatal(err)
		}
	},
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
