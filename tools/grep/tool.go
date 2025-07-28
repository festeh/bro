package grep

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"

	"github.com/revrost/go-openrouter"
)

type Args struct {
	Pattern string `json:"pattern"`
	Path    string `json:"path,omitempty"`    // directory or file to search in, defaults to current directory
	Context int    `json:"context,omitempty"` // number of lines of context to show around matches
}

type Result struct {
	Pattern  string   `json:"pattern"`
	Path     string   `json:"path"`
	Matches  []string `json:"matches"`
	Count    int      `json:"count"`
	Error    string   `json:"error,omitempty"`
}

// Tool represents the grep tool implementation
type Tool struct{}

// NewTool creates a new grep tool instance
func NewTool() *Tool {
	return &Tool{}
}

// Name returns the tool name
func (t *Tool) Name() string {
	return "grep"
}

// Description returns the tool description
func (t *Tool) Description() string {
	return GetDescription()
}

// Execute runs the rg command with the given arguments
func (t *Tool) Execute(args json.RawMessage) (string, error) {
	var grepArgs Args
	if err := json.Unmarshal(args, &grepArgs); err != nil {
		return "", err
	}

	// Build rg command arguments
	cmdArgs := []string{}

	// Add line numbers by default
	cmdArgs = append(cmdArgs, "--line-number")

	// Add color for better readability
	cmdArgs = append(cmdArgs, "--color", "never")

	// Add context if specified
	if grepArgs.Context > 0 {
		cmdArgs = append(cmdArgs, "--context", strconv.Itoa(grepArgs.Context))
	}

	// Add the pattern
	cmdArgs = append(cmdArgs, grepArgs.Pattern)

	// Add path if specified, otherwise search current directory
	if grepArgs.Path != "" {
		cmdArgs = append(cmdArgs, grepArgs.Path)
	} else {
		cmdArgs = append(cmdArgs, ".")
	}

	// Execute rg command
	cmd := exec.Command("rg", cmdArgs...)

	stdout, err := cmd.Output()

	// Build assistant message response
	var message strings.Builder

	if err != nil {
		// Handle errors
		if exitError, ok := err.(*exec.ExitError); ok {
			if exitError.ExitCode() == 1 {
				// Exit code 1 means no matches found (normal case for rg)
				message.WriteString(fmt.Sprintf("No matches found for pattern '%s'", grepArgs.Pattern))
				if grepArgs.Path != "" {
					message.WriteString(fmt.Sprintf(" in path '%s'", grepArgs.Path))
				}
			} else {
				// Other exit codes indicate actual errors
				message.WriteString(fmt.Sprintf("Error searching for pattern '%s': ", grepArgs.Pattern))
				if stderr := string(exitError.Stderr); stderr != "" {
					message.WriteString(stderr)
				} else {
					message.WriteString(fmt.Sprintf("rg exited with code %d", exitError.ExitCode()))
				}
			}
		} else {
			message.WriteString(fmt.Sprintf("Execution error: %s", err.Error()))
		}
		return strings.TrimSpace(message.String()), nil
	}

	// Parse output
	output := strings.TrimSpace(string(stdout))

	if output == "" {
		// No matches found
		message.WriteString(fmt.Sprintf("No matches found for pattern '%s'", grepArgs.Pattern))
		if grepArgs.Path != "" {
			message.WriteString(fmt.Sprintf(" in path '%s'", grepArgs.Path))
		}
	} else {
		// Matches found
		lines := strings.Split(output, "\n")
		
		// Count actual match lines (lines with line numbers, not context lines)
		matchCount := 0
		for _, line := range lines {
			// Match lines have format: filename:linenumber:content
			// Context lines have format: filename-linenumber-content
			if strings.Contains(line, ":") && !strings.HasPrefix(line, "--") {
				parts := strings.SplitN(line, ":", 3)
				if len(parts) >= 2 {
					// Check if second part is a number (line number)
					if _, err := strconv.Atoi(parts[1]); err == nil {
						matchCount++
					}
				}
			}
		}

		if matchCount == 1 {
			message.WriteString(fmt.Sprintf("Found 1 match for pattern '%s'", grepArgs.Pattern))
		} else {
			message.WriteString(fmt.Sprintf("Found %d matches for pattern '%s'", matchCount, grepArgs.Pattern))
		}

		if grepArgs.Path != "" {
			message.WriteString(fmt.Sprintf(" in path '%s'", grepArgs.Path))
		}

		if grepArgs.Context > 0 {
			message.WriteString(fmt.Sprintf(" (with %d lines of context)", grepArgs.Context))
		}

		message.WriteString(":\n\n")
		message.WriteString(output)
	}

	trimmedMessage := strings.TrimSpace(message.String())
	return trimmedMessage, nil
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
						"description": "Text pattern or regex to search for in files",
					},
					"path": map[string]interface{}{
						"type":        "string",
						"description": "Directory or file path to search in (defaults to current directory)",
					},
					"context": map[string]interface{}{
						"type":        "integer",
						"description": "Number of lines of context to show around matches (default: 0)",
						"minimum":     0,
						"maximum":     10,
					},
				},
				"required": []string{"pattern"},
			},
		},
	}
}