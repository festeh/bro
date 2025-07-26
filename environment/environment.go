package environment

import (
	"fmt"
	"os"
)

type Environment struct {
	APIKey string
}

func NewEnvironment() (*Environment, error) {
	apiKey := os.Getenv("OPENROUTER_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPENROUTER_API_KEY environment variable is required")
	}
	
	return &Environment{
		APIKey: apiKey,
	}, nil
}

func (e *Environment) IsConfigured() bool {
	return e.APIKey != ""
}