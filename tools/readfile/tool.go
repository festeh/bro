package readfile

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/revrost/go-openrouter"
)

type Args struct {
	Path string `json:"path"`
}

type Result struct {
	Path      string `json:"path"`
	Content   string `json:"content"`
	LineCount int    `json:"line_count"`
	FileSize  int64  `json:"file_size"`
	Truncated bool   `json:"truncated"`
	Error     string `json:"error,omitempty"`
}

const MAX_LINES = 200

// Tool represents the readfile tool implementation
type Tool struct{}

// NewTool creates a new readfile tool instance
func NewTool() *Tool {
	return &Tool{}
}

// Name returns the tool name
func (t *Tool) Name() string {
	return "readfile"
}

// Description returns the tool description
func (t *Tool) Description() string {
	return GetDescription()
}

// Execute reads a file with the given path
func (t *Tool) Execute(args json.RawMessage) (string, error) {
	var readArgs Args
	if err := json.Unmarshal(args, &readArgs); err != nil {
		return "", err
	}

	// Validate that path is provided
	if readArgs.Path == "" {
		return "Error: file path is required", nil
	}

	// Check if path is absolute
	if !filepath.IsAbs(readArgs.Path) {
		return fmt.Sprintf("Error: path must be absolute, got '%s'", readArgs.Path), nil
	}

	// Check if file exists
	fileInfo, err := os.Stat(readArgs.Path)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Sprintf("Error: file '%s' does not exist", readArgs.Path), nil
		}
		if os.IsPermission(err) {
			return fmt.Sprintf("Error: permission denied reading file '%s'", readArgs.Path), nil
		}
		return fmt.Sprintf("Error accessing file '%s': %s", readArgs.Path, err.Error()), nil
	}

	// Check if it's a directory
	if fileInfo.IsDir() {
		return fmt.Sprintf("Error: '%s' is a directory, not a file", readArgs.Path), nil
	}

	// Get file size
	fileSize := fileInfo.Size()

	// Open and read the file
	file, err := os.Open(readArgs.Path)
	if err != nil {
		return fmt.Sprintf("Error opening file '%s': %s", readArgs.Path, err.Error()), nil
	}
	defer file.Close()

	// Read file line by line
	var lines []string
	scanner := bufio.NewScanner(file)
	lineCount := 0

	for scanner.Scan() {
		lineCount++
		if lineCount <= MAX_LINES {
			lines = append(lines, scanner.Text())
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Sprintf("Error reading file '%s': %s", readArgs.Path, err.Error()), nil
	}

	// Build response message
	var message strings.Builder

	// Add file info header
	message.WriteString(fmt.Sprintf("File: %s\n", readArgs.Path))
	message.WriteString(fmt.Sprintf("Size: %d bytes, %d lines\n\n", fileSize, lineCount))

	// Add content
	if lineCount == 0 {
		message.WriteString("(empty file)")
	} else if lineCount <= MAX_LINES {
		// File is small enough, show all content
		for i, line := range lines {
			message.WriteString(fmt.Sprintf("%4d│ %s\n", i+1, line))
		}
	} else {
		// File is too long, show truncated content
		for i, line := range lines {
			message.WriteString(fmt.Sprintf("%4d│ %s\n", i+1, line))
		}
		message.WriteString("\n")
		message.WriteString("--- File truncated ---\n")
		message.WriteString(fmt.Sprintf("Showing first %d lines of %d total lines.\n", MAX_LINES, lineCount))
		message.WriteString(fmt.Sprintf("File continues for %d more lines...", lineCount-MAX_LINES))
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
						"description": "Absolute path to the file to read (e.g., /home/user/file.txt)",
					},
				},
				"required": []string{"path"},
			},
		},
	}
}
