/*
Copyright © 2024 NAME HERE <EMAIL ADDRESS>
*/
package main

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "hy-auth",
	Short: "An opinionated wrapper around hydroxide auth",
}

func main() {
	rootCmd.Execute()
}
