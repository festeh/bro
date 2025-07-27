package filefinder

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"

	"github.com/revrost/go-openrouter"
)

type Args struct {
	Pattern string `json:"pattern"`
	Type    string `json:"type,omitempty"`    // file, directory, symlink, etc.
	Glob    bool   `json:"glob,omitempty"`     // treat pattern as glob (default: regex)
}

type Result struct {
	Pattern   string   `json:"pattern"`
	Files     []string `json:"files"`
	Count     int      `json:"count"`
	Error     string   `json:"error,omitempty"`
}

// Tool represents the filefinder tool implementation
type Tool struct{}

// NewTool creates a new filefinder tool instance
func NewTool() *Tool {
	return &Tool{}
}

// Name returns the tool name
func (t *Tool) Name() string {
	return "filefinder"
}

// Description returns the tool description
func (t *Tool) Description() string {
	return GetDescription()
}

// Execute runs the fd command with the given arguments
func (t *Tool) Execute(args json.RawMessage) (interface{}, error) {
	var findArgs Args
	if err := json.Unmarshal(args, &findArgs); err != nil {
		return nil, err
	}
	
	// Build fd command arguments
	cmdArgs := []string{}
	
	// Add glob flag if needed
	if findArgs.Glob {
		cmdArgs = append(cmdArgs, "--glob")
	}
	
	// Add pattern
	if findArgs.Pattern != "" {
		cmdArgs = append(cmdArgs, findArgs.Pattern)
	}
	
	// Add type filter
	if findArgs.Type != "" {
		cmdArgs = append(cmdArgs, "--type", findArgs.Type)
	}
	
	// Execute fd command
	cmd := exec.Command("fd", cmdArgs...)
	
	stdout, err := cmd.Output()
	
	// Build assistant message response
	var message strings.Builder
	
	if err != nil {
		// Handle errors
		message.WriteString(fmt.Sprintf("Error searching for pattern '%s': ", findArgs.Pattern))
		if exitError, ok := err.(*exec.ExitError); ok {
			message.WriteString(string(exitError.Stderr))
		} else {
			message.WriteString(err.Error())
		}
		return message.String(), nil
	}
	
	// Parse output
	output := strings.TrimSpace(string(stdout))
	
	if output == "" {
		// No files found
		message.WriteString(fmt.Sprintf("No files found matching pattern '%s'", findArgs.Pattern))
		if findArgs.Type != "" {
			message.WriteString(fmt.Sprintf(" (type: %s)", findArgs.Type))
		}
	} else {
		// Files found
		files := strings.Split(output, "\n")
		count := len(files)
		
		if count == 1 {
			message.WriteString(fmt.Sprintf("Found 1 file matching pattern '%s':", findArgs.Pattern))
		} else {
			message.WriteString(fmt.Sprintf("Found %d files matching pattern '%s':", count, findArgs.Pattern))
		}
		
		if findArgs.Type != "" {
			message.WriteString(fmt.Sprintf(" (type: %s)", findArgs.Type))
		}
		
		message.WriteString("\n")
		for _, file := range files {
			message.WriteString(fmt.Sprintf("- %s\n", file))
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
					"pattern": map[string]interface{}{
						"type":        "string",
						"description": "Pattern or regex to search for files and directories",
					},
					"type": map[string]interface{}{
						"type":        "string",
						"description": "Filter by type: file, directory, symlink, executable, empty, socket, pipe",
						"enum":        []string{"file", "directory", "symlink", "executable", "empty", "socket", "pipe"},
					},
					"glob": map[string]interface{}{
						"type":        "boolean",
						"description": "Treat pattern as glob instead of regex (default: false)",
					},
				},
				"required": []string{"pattern"},
			},
		},
	}
}