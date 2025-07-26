package bash

import (
	"encoding/json"
	"os/exec"

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
func (t *Tool) Execute(args json.RawMessage) (interface{}, error) {
	var bashArgs Args
	if err := json.Unmarshal(args, &bashArgs); err != nil {
		return nil, err
	}
	
	cmd := exec.Command("bash", "-c", bashArgs.Command)
	
	stdout, err := cmd.Output()
	result := Result{
		Command:  bashArgs.Command,
		Stdout:   string(stdout),
		ExitCode: 0,
	}
	
	if exitError, ok := err.(*exec.ExitError); ok {
		result.ExitCode = exitError.ExitCode()
		result.Stderr = string(exitError.Stderr)
	} else if err != nil {
		result.Error = err.Error()
		result.ExitCode = -1
	}
	
	return result, nil
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

// Legacy functions for backward compatibility
func Execute(args Args) Result {
	tool := NewTool()
	result, _ := tool.Execute(mustMarshal(args))
	return result.(Result)
}

func GetDefinition() map[string]interface{} {
	tool := NewTool()
	def := tool.GetDefinition()
	return map[string]interface{}{
		"type": string(def.Type),
		"function": map[string]interface{}{
			"name":        def.Function.Name,
			"description": def.Function.Description,
			"parameters":  def.Function.Parameters,
		},
	}
}

func mustMarshal(v interface{}) json.RawMessage {
	data, _ := json.Marshal(v)
	return data
}