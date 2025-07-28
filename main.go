package main

import (
	"os"
	"path/filepath"

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

	// Initialize ~/.bro directory and models.txt
	if err := initializeBroDirectory(); err != nil {
		log.Error("Failed to initialize ~/.bro directory", "error", err)
	}

	p := tea.NewProgram(app.NewApp())

	if _, err := p.Run(); err != nil {
		log.Error("Failed to run program", "error", err)
	}

	log.Info("Application exiting")
}

func initializeBroDirectory() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	broDir := filepath.Join(homeDir, ".bro")
	
	// Create ~/.bro directory if it doesn't exist
	if err := os.MkdirAll(broDir, 0755); err != nil {
		return err
	}

	modelsFile := filepath.Join(broDir, "models.txt")
	
	// Check if models.txt exists, if not create it by calling UpdateModels
	if _, err := os.Stat(modelsFile); os.IsNotExist(err) {
		log.Info("models.txt not found, creating it...")
		return app.UpdateModels()
	}

	return nil
}

