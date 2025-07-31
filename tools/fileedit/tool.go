package fileedit

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/revrost/go-openrouter"
)

type Args struct {
	Path      string `json:"path"`
	OldString string `json:"old_string"`
	NewString string `json:"new_string"`
}

type Result struct {
	Path         string `json:"path"`
	OldString    string `json:"old_string"`
	NewString    string `json:"new_string"`
	Success      bool   `json:"success"`
	BytesWritten int    `json:"bytes_written"`
	Error        string `json:"error,omitempty"`
}

// Tool represents the fileedit tool implementation
type Tool struct{}

// NewTool creates a new fileedit tool instance
func NewTool() *Tool {
	return &Tool{}
}

// Name returns the tool name
func (t *Tool) Name() string {
	return "fileedit"
}

// Description returns the tool description
func (t *Tool) Description() string {
	return GetDescription()
}

// Execute performs the file edit with the given arguments
func (t *Tool) Execute(args json.RawMessage) (string, error) {
	var editArgs Args
	if err := json.Unmarshal(args, &editArgs); err != nil {
		return "", err
	}

	// Validate required arguments
	if editArgs.Path == "" {
		return "Error: file path is required", nil
	}
	if editArgs.OldString == "" {
		return "Error: old_string is required and cannot be empty", nil
	}

	// Check if path is absolute
	if !filepath.IsAbs(editArgs.Path) {
		return fmt.Sprintf("Error: path must be absolute, got '%s'", editArgs.Path), nil
	}

	// Check if file exists and is readable
	fileInfo, err := os.Stat(editArgs.Path)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Sprintf("Error: file '%s' does not exist", editArgs.Path), nil
		}
		if os.IsPermission(err) {
			return fmt.Sprintf("Error: permission denied accessing file '%s'", editArgs.Path), nil
		}
		return fmt.Sprintf("Error accessing file '%s': %s", editArgs.Path, err.Error()), nil
	}

	// Check if it's a directory
	if fileInfo.IsDir() {
		return fmt.Sprintf("Error: '%s' is a directory, not a file", editArgs.Path), nil
	}

	// Read the entire file
	content, err := os.ReadFile(editArgs.Path)
	if err != nil {
		return fmt.Sprintf("Error reading file '%s': %s", editArgs.Path, err.Error()), nil
	}

	contentStr := string(content)

	// Check if the old string exists in the file
	if !strings.Contains(contentStr, editArgs.OldString) {
		return fmt.Sprintf("Error: string '%s' not found in file '%s'", editArgs.OldString, editArgs.Path), nil
	}

	// Count occurrences to ensure uniqueness
	occurrences := strings.Count(contentStr, editArgs.OldString)
	if occurrences > 1 {
		return fmt.Sprintf("Error: string '%s' appears %d times in file '%s'. String must be unique to avoid ambiguity",
			editArgs.OldString, occurrences, editArgs.Path), nil
	}

	// Perform the replacement
	newContent := strings.Replace(contentStr, editArgs.OldString, editArgs.NewString, 1)

	// Write the modified content back to the file
	err = os.WriteFile(editArgs.Path, []byte(newContent), fileInfo.Mode())
	if err != nil {
		return fmt.Sprintf("Error writing to file '%s': %s", editArgs.Path, err.Error()), nil
	}

	// Build success message
	var message strings.Builder
	message.WriteString(fmt.Sprintf("Successfully edited file: %s\n", editArgs.Path))
	message.WriteString(fmt.Sprintf("Replaced: '%s'\n", editArgs.OldString))
	message.WriteString(fmt.Sprintf("With: '%s'\n", editArgs.NewString))
	message.WriteString(fmt.Sprintf("File size: %d bytes", len(newContent)))

	// Add change summary if strings are different lengths
	oldLen := len(editArgs.OldString)
	newLen := len(editArgs.NewString)
	if oldLen != newLen {
		diff := newLen - oldLen
		if diff > 0 {
			message.WriteString(fmt.Sprintf(" (+%d bytes)", diff))
		} else {
			message.WriteString(fmt.Sprintf(" (%d bytes)", diff))
		}
	}

	return strings.TrimSpace(message.String()), nil
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
					"path": map[string]interface{}{
						"type":        "string",
						"description": "Absolute path to the file to edit (e.g., /home/user/file.txt)",
					},
					"old_string": map[string]interface{}{
						"type":        "string",
						"description": "Exact string to find and replace (must be unique in the file)",
					},
					"new_string": map[string]interface{}{
						"type":        "string",
						"description": "String to replace the old string with (can be empty for deletion)",
					},
				},
				"required": []string{"path", "old_string", "new_string"},
			},
		},
	}
}
