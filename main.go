package main

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/festeh/bro/app"
)

func main() {
	p := tea.NewProgram(app.NewApp())

	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v", err)
	}
}

