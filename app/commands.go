package app

import (
	"fmt"
	"strings"

	"github.com/festeh/bro/config"
	"github.com/festeh/bro/openrouter"
)


func (a *App) handleUserCommand(input string) bool {
	if !strings.HasPrefix(input, "/") {
		return false
	}

	cmd := strings.ToLower(strings.TrimSpace(strings.TrimPrefix(input, "/")))
	if cmd == "help" {
		a.mode = "help"
		a.input = ""
		return true
	}

	if cmd == "update-models" {
		if err := config.UpdateModels(); err != nil {
			a.messages = append(a.messages, openrouter.NewCommandResponseMessage(fmt.Sprintf("Error updating models: %v", err)))
		} else {
			if err := a.config.UpdateAvailableModels(); err != nil {
				a.messages = append(a.messages, openrouter.NewCommandResponseMessage(fmt.Sprintf("Models updated but failed to reload: %v", err)))
			} else {
				a.messages = append(a.messages, openrouter.NewCommandResponseMessage("Models updated successfully!"))
			}
		}
		a.input = ""
		return true
	}

	if strings.HasPrefix(cmd, "model") {
		modelName := strings.TrimSpace(strings.TrimPrefix(cmd, "model"))
		if modelName == "" {
			currentModel := a.client.GetModel()
			a.messages = append(a.messages, openrouter.NewCommandResponseMessage(fmt.Sprintf("Current model: %s", currentModel)))
		} else {
			if a.config == nil || len(a.config.AvailableModels) == 0 {
				a.messages = append(a.messages, openrouter.NewCommandErrorResponseMessage("Error: Available models not loaded"))
			} else if !a.config.IsValidModel(modelName) {
				a.messages = append(a.messages, openrouter.NewCommandErrorResponseMessage(fmt.Sprintf("Model '%s' is not available. Available models:\n%s", modelName, strings.Join(a.config.AvailableModels, "\n"))))
			} else {
				a.client.SetModel(modelName)
				a.messages = append(a.messages, openrouter.NewCommandResponseMessage(fmt.Sprintf("Model set to: %s", modelName)))
			}
		}
		a.input = ""
		return true
	}

	// Command not recognized
	a.messages = append(a.messages, openrouter.NewCommandErrorResponseMessage("Command not recognized: "+input))
	a.input = ""
	return true
}

