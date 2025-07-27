package main

import (
	"os"

	"github.com/charmbracelet/log"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/festeh/bro/app"
)

func main() {
	// Set up file logging to log.txt (recreated on each start)
	logFile, err := os.Create("log.txt")
	if err != nil {
		log.Fatal("Failed to create log file", "error", err)
	}
	defer logFile.Close()

	// Configure charmbracelet/log to write to both file and stderr
	log.SetOutput(logFile)
	log.SetLevel(log.InfoLevel)

	log.Info("Application starting")

	p := tea.NewProgram(app.NewApp())

	if _, err := p.Run(); err != nil {
		log.Error("Failed to run program", "error", err)
	}

	log.Info("Application exiting")
}

