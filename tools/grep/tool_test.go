package grep

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestGrepTool(t *testing.T) {
	tool := NewTool()

	// Test basic functionality
	t.Run("basic search", func(t *testing.T) {
		args := Args{
			Pattern: "package",
			Path:    ".",
			Context: 0,
		}

		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Grep result: %s", message)

		// Basic validation that we got a proper response
		if !strings.Contains(message, "package") && !strings.Contains(message, "No matches found") {
			t.Errorf("Expected response to mention 'package' or 'No matches found', got: %s", message)
		}
	})

	// Test with context
	t.Run("search with context", func(t *testing.T) {
		args := Args{
			Pattern: "func",
			Path:    ".",
			Context: 2,
		}

		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Grep with context result: %s", message)

		// Should mention context in the response if matches are found
		if strings.Contains(message, "Found") && strings.Contains(message, "match") {
			if !strings.Contains(message, "context") {
				t.Errorf("Expected response to mention context when matches found, got: %s", message)
			}
		}
	})

	// Test invalid pattern
	t.Run("invalid pattern", func(t *testing.T) {
		args := Args{
			Pattern: "[invalid regex",
			Path:    ".",
			Context: 0,
		}

		argsJSON, err := json.Marshal(args)
		if err != nil {
			t.Fatalf("Failed to marshal args: %v", err)
		}

		result, err := tool.Execute(argsJSON)
		if err != nil {
			t.Fatalf("Tool execution failed: %v", err)
		}

		message := result
		t.Logf("Invalid pattern result: %s", message)

		// Should handle the error gracefully
		if !strings.Contains(message, "Error") && !strings.Contains(message, "No matches found") {
			t.Errorf("Expected error handling for invalid regex, got: %s", message)
		}
	})
}

func TestGrepToolDefinition(t *testing.T) {
	tool := NewTool()

	// Test tool metadata
	if tool.Name() != "grep" {
		t.Errorf("Expected tool name 'grep', got '%s'", tool.Name())
	}

	description := tool.Description()
	if description == "" {
		t.Error("Tool description should not be empty")
	}

	// Test OpenRouter definition
	def := tool.GetDefinition()
	if def.Function.Name != "grep" {
		t.Errorf("Expected function name 'grep', got '%s'", def.Function.Name)
	}

	// Check required parameters
	params := def.Function.Parameters.(map[string]interface{})
	props := params["properties"].(map[string]interface{})

	if _, exists := props["pattern"]; !exists {
		t.Error("Expected 'pattern' parameter to exist")
	}

	required := params["required"].([]string)
	if len(required) != 1 || required[0] != "pattern" {
		t.Errorf("Expected required parameters to be ['pattern'], got %v", required)
	}
}
