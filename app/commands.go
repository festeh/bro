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
			a.messages = append(a.messages, openrouter.NewCommandResponseMessage("Models updated successfully!"))
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
			a.client.SetModel(modelName)
			a.messages = append(a.messages, openrouter.NewCommandResponseMessage(fmt.Sprintf("Model set to: %s", modelName)))
		}
		a.input = ""
		return true
	}

	// Command not recognized
	a.messages = append(a.messages, openrouter.NewCommandErrorResponseMessage("Command not recognized: "+input))
	a.input = ""
	return true
}

