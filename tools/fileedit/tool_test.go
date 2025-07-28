package fileedit

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFileEditTool(t *testing.T) {
	tool := NewTool()

	// Create temp directory for test files
	tempDir, err := os.MkdirTemp("", "fileedit_test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Test successful edit with unique string
	t.Run("successful edit with unique string", func(t *testing.T) {
		// Create test file
		testFile := filepath.Join(tempDir, "test1.txt")
		originalContent := "Hello world\nThis is a test\nGoodbye world"
		err := os.WriteFile(testFile, []byte(originalContent), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{
			Path:      testFile,
			OldString: "This is a test",
			NewString: "This is modified",
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
		t.Logf("Successful edit result: %s", message)

		// Verify success message
		if !strings.Contains(message, "Successfully edited file") {
			t.Errorf("Expected success message, got: %s", message)
		}
		if !strings.Contains(message, testFile) {
			t.Errorf("Expected file path in result, got: %s", message)
		}

		// Verify file content was changed
		newContent, err := os.ReadFile(testFile)
		if err != nil {
			t.Fatalf("Failed to read modified file: %v", err)
		}

		expectedContent := "Hello world\nThis is modified\nGoodbye world"
		if string(newContent) != expectedContent {
			t.Errorf("Expected content '%s', got '%s'", expectedContent, string(newContent))
		}
	})

	// Test replacement with empty string (deletion)
	t.Run("replace with empty string", func(t *testing.T) {
		testFile := filepath.Join(tempDir, "test2.txt")
		originalContent := "Keep this\nDelete this line\nKeep this too"
		err := os.WriteFile(testFile, []byte(originalContent), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{
			Path:      testFile,
			OldString: "Delete this line\n",
			NewString: "",
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
		t.Logf("Delete line result: %s", message)

		// Verify file content
		newContent, err := os.ReadFile(testFile)
		if err != nil {
			t.Fatalf("Failed to read modified file: %v", err)
		}

		expectedContent := "Keep this\nKeep this too"
		if string(newContent) != expectedContent {
			t.Errorf("Expected content '%s', got '%s'", expectedContent, string(newContent))
		}
	})

	// Test string not found error
	t.Run("string not found", func(t *testing.T) {
		testFile := filepath.Join(tempDir, "test3.txt")
		originalContent := "Hello world\nThis is a test"
		err := os.WriteFile(testFile, []byte(originalContent), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{
			Path:      testFile,
			OldString: "non-existent string",
			NewString: "replacement",
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
		t.Logf("String not found result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message, got: %s", message)
		}
		if !strings.Contains(message, "not found") {
			t.Errorf("Expected 'not found' in error message, got: %s", message)
		}

		// Verify file was not modified
		content, err := os.ReadFile(testFile)
		if err != nil {
			t.Fatalf("Failed to read file: %v", err)
		}
		if string(content) != originalContent {
			t.Errorf("File should not have been modified")
		}
	})

	// Test ambiguous string error (multiple occurrences)
	t.Run("ambiguous string with multiple occurrences", func(t *testing.T) {
		testFile := filepath.Join(tempDir, "test4.txt")
		originalContent := "test line\nanother test line\nfinal test line"
		err := os.WriteFile(testFile, []byte(originalContent), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{
			Path:      testFile,
			OldString: "test line",
			NewString: "modified line",
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
		t.Logf("Ambiguous string result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message, got: %s", message)
		}
		if !strings.Contains(message, "appears 3 times") {
			t.Errorf("Expected occurrence count in error message, got: %s", message)
		}
		if !strings.Contains(message, "must be unique") {
			t.Errorf("Expected uniqueness requirement in error message, got: %s", message)
		}

		// Verify file was not modified
		content, err := os.ReadFile(testFile)
		if err != nil {
			t.Fatalf("Failed to read file: %v", err)
		}
		if string(content) != originalContent {
			t.Errorf("File should not have been modified")
		}
	})

	// Test non-existent file
	t.Run("non-existent file", func(t *testing.T) {
		args := Args{
			Path:      "/nonexistent/file.txt",
			OldString: "old",
			NewString: "new",
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
		t.Logf("Non-existent file result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message, got: %s", message)
		}
		if !strings.Contains(message, "does not exist") {
			t.Errorf("Expected 'does not exist' in error message, got: %s", message)
		}
	})

	// Test relative path (should fail)
	t.Run("relative path", func(t *testing.T) {
		args := Args{
			Path:      "relative/path.txt",
			OldString: "old",
			NewString: "new",
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
		t.Logf("Relative path result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message, got: %s", message)
		}
		if !strings.Contains(message, "must be absolute") {
			t.Errorf("Expected 'must be absolute' in error message, got: %s", message)
		}
	})

	// Test directory instead of file
	t.Run("directory instead of file", func(t *testing.T) {
		args := Args{
			Path:      tempDir,
			OldString: "old",
			NewString: "new",
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
		t.Logf("Directory result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message, got: %s", message)
		}
		if !strings.Contains(message, "is a directory") {
			t.Errorf("Expected 'is a directory' in error message, got: %s", message)
		}
	})

	// Test empty old_string
	t.Run("empty old_string", func(t *testing.T) {
		testFile := filepath.Join(tempDir, "test5.txt")
		originalContent := "Some content"
		err := os.WriteFile(testFile, []byte(originalContent), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{
			Path:      testFile,
			OldString: "",
			NewString: "new",
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
		t.Logf("Empty old_string result: %s", message)

		if !strings.Contains(message, "Error") {
			t.Errorf("Expected error message, got: %s", message)
		}
		if !strings.Contains(message, "old_string is required") {
			t.Errorf("Expected 'old_string is required' in error message, got: %s", message)
		}
	})

	// Test multiline string replacement
	t.Run("multiline string replacement", func(t *testing.T) {
		testFile := filepath.Join(tempDir, "test6.txt")
		originalContent := "Line 1\nOld block\nline 2\nline 3\nEnd"
		err := os.WriteFile(testFile, []byte(originalContent), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		args := Args{
			Path:      testFile,
			OldString: "Old block\nline 2\nline 3",
			NewString: "New block\nsingle line",
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
		t.Logf("Multiline replacement result: %s", message)

		// Verify file content
		newContent, err := os.ReadFile(testFile)
		if err != nil {
			t.Fatalf("Failed to read modified file: %v", err)
		}

		expectedContent := "Line 1\nNew block\nsingle line\nEnd"
		if string(newContent) != expectedContent {
			t.Errorf("Expected content '%s', got '%s'", expectedContent, string(newContent))
		}
	})
}

func TestFileEditToolDefinition(t *testing.T) {
	tool := NewTool()

	// Test tool metadata
	if tool.Name() != "fileedit" {
		t.Errorf("Expected tool name 'fileedit', got '%s'", tool.Name())
	}

	description := tool.Description()
	if description == "" {
		t.Error("Tool description should not be empty")
	}

	// Test OpenRouter definition
	def := tool.GetDefinition()
	if def.Function.Name != "fileedit" {
		t.Errorf("Expected function name 'fileedit', got '%s'", def.Function.Name)
	}

	// Check required parameters
	params := def.Function.Parameters.(map[string]interface{})
	props := params["properties"].(map[string]interface{})
	
	requiredFields := []string{"path", "old_string", "new_string"}
	for _, field := range requiredFields {
		if _, exists := props[field]; !exists {
			t.Errorf("Expected '%s' parameter to exist", field)
		}
	}

	required := params["required"].([]string)
	if len(required) != 3 {
		t.Errorf("Expected 3 required parameters, got %d", len(required))
	}

	expectedRequired := map[string]bool{"path": true, "old_string": true, "new_string": true}
	for _, param := range required {
		if !expectedRequired[param] {
			t.Errorf("Unexpected required parameter: %s", param)
		}
	}
}