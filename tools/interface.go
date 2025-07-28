package tools

import (
	"encoding/json"
	"fmt"

	"github.com/revrost/go-openrouter"
)

// Tool represents a tool that can be called by the LLM
type Tool interface {
	// Name returns the unique name of the tool
	Name() string
	
	// Description returns a detailed description of what the tool does and when to use it
	Description() string
	
	// Execute runs the tool with the given arguments and returns the result
	Execute(args json.RawMessage) (string, error)
	
	// GetDefinition returns the OpenRouter tool definition for this tool
	GetDefinition() openrouter.Tool
}

// Registry holds all available tools
type Registry struct {
	tools map[string]Tool
}

// NewRegistry creates a new tool registry
func NewRegistry() *Registry {
	return &Registry{
		tools: make(map[string]Tool),
	}
}

// Register adds a tool to the registry
func (r *Registry) Register(tool Tool) {
	r.tools[tool.Name()] = tool
}

// Get retrieves a tool by name
func (r *Registry) Get(name string) (Tool, bool) {
	tool, exists := r.tools[name]
	return tool, exists
}

// GetAll returns all registered tools
func (r *Registry) GetAll() []Tool {
	var tools []Tool
	for _, tool := range r.tools {
		tools = append(tools, tool)
	}
	return tools
}

// GetDefinitions returns OpenRouter tool definitions for all registered tools
func (r *Registry) GetDefinitions() []openrouter.Tool {
	var definitions []openrouter.Tool
	for _, tool := range r.tools {
		definitions = append(definitions, tool.GetDefinition())
	}
	return definitions
}

// ExecuteTool executes a tool by name with the given arguments using the provided registry
func ExecuteTool(registry *Registry, name string, args json.RawMessage) (string, error) {
	tool, exists := registry.Get(name)
	if !exists {
		return "", fmt.Errorf("tool '%s' not found", name)
	}

	return tool.Execute(args)
}