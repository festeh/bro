package main

import (
	"github.com/charmbracelet/log"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/festeh/bro/app"
)

func main() {
	p := tea.NewProgram(app.NewApp())

	if _, err := p.Run(); err != nil {
		log.Error("Failed to run program", "error", err)
	}
}

