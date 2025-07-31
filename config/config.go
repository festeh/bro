package config

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/log"
	"slices"
)

type Config struct {
	AvailableModels []string
	History         History
	Session         Session
	Stats           *Stats
}

func InitializeBroDirectory() (*Config, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	broDir := filepath.Join(homeDir, ".bro")

	// Create ~/.bro directory if it doesn't exist
	if err := os.MkdirAll(broDir, 0755); err != nil {
		return nil, err
	}

	modelsFile := filepath.Join(broDir, "models.txt")

	// Check if models.txt exists, if not create it by calling UpdateModels
	if _, err := os.Stat(modelsFile); os.IsNotExist(err) {
		log.Info("models.txt not found, creating it...")
		if err := UpdateModels(); err != nil {
			return nil, err
		}
	}

	// Initialize config and load available models
	config := &Config{}
	if err := loadAvailableModels(config); err != nil {
		return nil, err
	}

	// Initialize history
	history, err := NewHistory()
	if err != nil {
		log.Error("Failed to initialize history", "error", err)
		// Create empty history as fallback
		config.History = History{
			commands: make([]string, HISTORY_SIZE),
			head:     0,
			size:     0,
			dirPath:  filepath.Join(homeDir, ".bro"),
		}
	} else {
		config.History = *history
	}

	// Initialize session
	session, err := NewSession()
	if err != nil {
		log.Error("Failed to initialize session", "error", err)
		// Create empty session as fallback
		config.Session = Session{
			dirPath:     filepath.Join(homeDir, ".bro"),
			sessionFile: nil,
		}
	} else {
		config.Session = *session
	}

	// Initialize stats
	stats, err := NewStats()
	if err != nil {
		log.Error("Failed to initialize stats", "error", err)
		config.Stats = nil
	} else {
		config.Stats = stats
	}

	return config, nil
}

func UpdateModels() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	modelsFile := filepath.Join(homeDir, ".bro", "models.txt")

	// Create a basic models.txt file with some default models
	models := []string{
		"anthropic/claude-sonnet-4",
		"x-ai/grok-4",
		"qwen/qwen3-coder",
		"openai/gpt-4o",
		"meta-llama/llama-3.1-405b-instruct",
		"google/gemini-2.0-flash-exp",
	}
	modelsContent := strings.Join(models, "\n")

	if err := os.WriteFile(modelsFile, []byte(modelsContent), 0644); err != nil {
		return err
	}

	log.Info("Updated models.txt successfully")
	return nil
}

func (c *Config) UpdateAvailableModels() error {
	return loadAvailableModels(c)
}

func loadAvailableModels(config *Config) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	modelsFile := filepath.Join(homeDir, ".bro", "models.txt")
	file, err := os.Open(modelsFile)
	if err != nil {
		return err
	}
	defer file.Close()

	var models []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			models = append(models, line)
		}
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	config.AvailableModels = models
	return nil
}

func (c *Config) IsValidModel(modelName string) bool {
	if c == nil {
		return false
	}
	return slices.Contains(c.AvailableModels, modelName)
}
