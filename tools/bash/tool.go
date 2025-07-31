package bash

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"

	"github.com/revrost/go-openrouter"
)

type Args struct {
	Command string `json:"command"`
}

type Result struct {
	Command  string `json:"command"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exit_code"`
	Error    string `json:"error,omitempty"`
}

// Tool represents the bash tool implementation
type Tool struct{}

// NewTool creates a new bash tool instance
func NewTool() *Tool {
	return &Tool{}
}

// Name returns the tool name
func (t *Tool) Name() string {
	return "bash"
}

// Description returns the tool description
func (t *Tool) Description() string {
	return GetDescription()
}

// Execute runs the bash command with the given arguments
func (t *Tool) Execute(args json.RawMessage) (string, error) {
	var bashArgs Args
	if err := json.Unmarshal(args, &bashArgs); err != nil {
		return "", err
	}

	cmd := exec.Command("bash", "-c", bashArgs.Command)

	stdout, err := cmd.Output()

	// Build assistant message response
	var message strings.Builder

	if exitError, ok := err.(*exec.ExitError); ok {
		// Command failed with non-zero exit code
		message.WriteString(fmt.Sprintf("Command failed with exit code %d:\n", exitError.ExitCode()))
		if stderr := string(exitError.Stderr); stderr != "" {
			message.WriteString(fmt.Sprintf("Error: %s\n", stderr))
		}
		if stdout := string(stdout); stdout != "" {
			message.WriteString(fmt.Sprintf("Output: %s\n", stdout))
		}
	} else if err != nil {
		// Execution error
		message.WriteString(fmt.Sprintf("Execution error: %s", err.Error()))
	} else {
		// Success
		if output := string(stdout); output != "" {
			message.WriteString(strings.TrimSpace(output))
		} else {
			message.WriteString("Command completed successfully (no output)")
		}
	}

	return message.String(), nil
}

// GetDefinition returns the OpenRouter tool definition
func (t *Tool) GetDefinition() openrouter.Tool {
	return openrouter.Tool{
		Type: openrouter.ToolTypeFunction,
		Function: &openrouter.FunctionDefinition{
			Name:        t.Name(),
			Description: t.Description(),
			Parameters: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"command": map[string]interface{}{
						"type":        "string",
						"description": "The bash command to execute",
					},
				},
				"required": []string{"command"},
			},
		},
	}
}
