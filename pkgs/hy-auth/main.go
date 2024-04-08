/*
Copyright © 2024 NAME HERE <EMAIL ADDRESS>
*/
package main

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
)

var (
	codeStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.AdaptiveColor{
		Light: "#040911",
		Dark:  "#547ebc",
	})
	rootCmd = &cobra.Command{
		Use:   "hy-auth",
		Short: fmt.Sprintf("An opinionated wrapper around %v", codeStyle.Render("hydroxide auth")),
	}
)

func main() {
	rootCmd.Execute()
}
