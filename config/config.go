package config

import (
	"os"
	"path/filepath"

	"github.com/charmbracelet/log"
)

func InitializeBroDirectory() error {
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
		return UpdateModels()
	}

	return nil
}

func UpdateModels() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	modelsFile := filepath.Join(homeDir, ".bro", "models.txt")
	
	// Create a basic models.txt file with some default models
	modelsContent := `anthropic/claude-sonnet-4
x-ai/grok-4
qwen/qwen3-coder
openai/gpt-4o
meta-llama/llama-3.1-405b-instruct
google/gemini-2.0-flash-exp
`

	if err := os.WriteFile(modelsFile, []byte(modelsContent), 0644); err != nil {
		return err
	}

	log.Info("Updated models.txt successfully")
	return nil
}