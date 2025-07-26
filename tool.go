package main

import (
	"encoding/json"
	"os/exec"
)

type ToolCall struct {
	ID       string                 `json:"id"`
	Type     string                 `json:"type"`
	Function ToolCallFunction       `json:"function"`
}

type ToolCallFunction struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

type ToolResult struct {
	ToolCallID string `json:"tool_call_id"`
	Content    string `json:"content"`
}

type BashToolArgs struct {
	Command string `json:"command"`
}

type BashToolResult struct {
	Command  string `json:"command"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exit_code"`
	Error    string `json:"error,omitempty"`
}

func ExecuteBashTool(args BashToolArgs) BashToolResult {
	cmd := exec.Command("bash", "-c", args.Command)
	
	stdout, err := cmd.Output()
	result := BashToolResult{
		Command:  args.Command,
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
	
	return result
}

func GetBashToolDefinition() map[string]interface{} {
	return map[string]interface{}{
		"type": "function",
		"function": map[string]interface{}{
			"name":        "bash",
			"description": "Execute a bash command in the terminal and return the output",
			"parameters": map[string]interface{}{
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