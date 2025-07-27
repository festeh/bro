package main

import (
	"encoding/json"
	"fmt"
	
	"github.com/festeh/bro/tools"
	"github.com/festeh/bro/tools/bash"
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

// ExecuteTool executes a tool by name with the given arguments using the provided registry
func ExecuteTool(registry *tools.Registry, name string, args json.RawMessage) (interface{}, error) {
	tool, exists := registry.Get(name)
	if !exists {
		return nil, fmt.Errorf("tool '%s' not found", name)
	}
	
	return tool.Execute(args)
}

