package readfile

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadFileTool(t *testing.T) {
	tool := NewTool()

	// Create temp directory for test files
	tempDir, err := os.MkdirTemp("", "readfile_test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Test reading a small file
	t.Run("read small file", func(t *testing.T) {
		// Create a small test file
		testFile := filepath.Join(tempDir, "small.txt")
		content := "line 1\nline 2\nline 3\n"
		err := os.WriteFile(testFile, []byte(content), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{Path: testFile}
		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Small file result: %s", message)

		// Should contain file path, line numbers, and content
		if !strings.Contains(message, testFile) {
			t.Errorf("Expected file path in result, got: %s", message)
		}
		if !strings.Contains(message, "3 lines") {
			t.Errorf("Expected line count in result, got: %s", message)
		}
		if !strings.Contains(message, "line 1") {
			t.Errorf("Expected file content in result, got: %s", message)
		}
		if strings.Contains(message, "truncated") {
			t.Errorf("Small file should not be truncated, got: %s", message)
		}
	})

	// Test reading a large file (> 200 lines)
	t.Run("read large file with truncation", func(t *testing.T) {
		// Create a large test file
		testFile := filepath.Join(tempDir, "large.txt")
		var content strings.Builder
		for i := 1; i <= 250; i++ {
			content.WriteString(fmt.Sprintf("This is line %d\n", i))
		}
		err := os.WriteFile(testFile, []byte(content.String()), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{Path: testFile}
		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Large file result length: %d", len(message))

		// Should contain truncation message
		if !strings.Contains(message, "truncated") {
			t.Errorf("Large file should be truncated, got: %s", message)
		}
		if !strings.Contains(message, "250 total lines") {
			t.Errorf("Expected total line count in result, got: %s", message)
		}
		if !strings.Contains(message, "first 200 lines") {
			t.Errorf("Expected truncation info in result, got: %s", message)
		}
		// Should contain first line but not last line
		if !strings.Contains(message, "This is line 1") {
			t.Errorf("Expected first line in result, got: %s", message)
		}
		if strings.Contains(message, "This is line 250") {
			t.Errorf("Should not contain last line due to truncation, got: %s", message)
		}
	})

	// Test reading empty file
	t.Run("read empty file", func(t *testing.T) {
		testFile := filepath.Join(tempDir, "empty.txt")
		err := os.WriteFile(testFile, []byte(""), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{Path: testFile}
		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Empty file result: %s", message)

		if !strings.Contains(message, "0 lines") {
			t.Errorf("Expected 0 lines for empty file, got: %s", message)
		}
		if !strings.Contains(message, "(empty file)") {
			t.Errorf("Expected empty file message, got: %s", message)
		}
	})

	// Test non-existent file
	t.Run("read non-existent file", func(t *testing.T) {
		args := Args{Path: "/nonexistent/file.txt"}
		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Non-existent file result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message for non-existent file, got: %s", message)
		}
		if !strings.Contains(message, "does not exist") {
			t.Errorf("Expected 'does not exist' in error message, got: %s", message)
		}
	})

	// Test relative path (should fail)
	t.Run("read with relative path", func(t *testing.T) {
		args := Args{Path: "relative/path.txt"}
		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Relative path result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message for relative path, got: %s", message)
		}
		if !strings.Contains(message, "must be absolute") {
			t.Errorf("Expected 'must be absolute' in error message, got: %s", message)
		}
	})

	// Test directory instead of file
	t.Run("read directory", func(t *testing.T) {
		args := Args{Path: tempDir}
		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Directory result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message for directory, got: %s", message)
		}
		if !strings.Contains(message, "is a directory") {
			t.Errorf("Expected 'is a directory' in error message, got: %s", message)
		}
	})
}

func TestReadFileToolDefinition(t *testing.T) {
	tool := NewTool()

	// Test tool metadata
	if tool.Name() != "readfile" {
		t.Errorf("Expected tool name 'readfile', got '%s'", tool.Name())
	}

	description := tool.Description()
	if description == "" {
		t.Error("Tool description should not be empty")
	}

	// Test OpenRouter definition
	def := tool.GetDefinition()
	if def.Function.Name != "readfile" {
		t.Errorf("Expected function name 'readfile', got '%s'", def.Function.Name)
	}

	// Check required parameters
	params := def.Function.Parameters.(map[string]interface{})
	props := params["properties"].(map[string]interface{})

	if _, exists := props["path"]; !exists {
		t.Error("Expected 'path' parameter to exist")
	}

	required := params["required"].([]string)
	if len(required) != 1 || required[0] != "path" {
		t.Errorf("Expected required parameters to be ['path'], got %v", required)
	}
}
