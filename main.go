package main

import (
	"github.com/charmbracelet/log"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/festeh/bro/app"
	"github.com/festeh/bro/config"
	"os"
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

	// Initialize ~/.bro directory and models.txt
	if _, err := config.InitializeBroDirectory(); err != nil {
		log.Error("Failed to initialize ~/.bro directory", "error", err)
	}

	p := tea.NewProgram(app.NewApp())

	if _, err := p.Run(); err != nil {
		log.Error("Failed to run program", "error", err)
	}

	log.Info("Application exiting")
}


