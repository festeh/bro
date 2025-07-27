package main

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	p := tea.NewProgram(NewApp())

	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v", err)
	}
}

