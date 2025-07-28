package filefinder_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/festeh/bro/environment"
	"github.com/festeh/bro/openrouter"
	"github.com/festeh/bro/tools/filefinder"
)

func TestFileFinderToolWithAI(t *testing.T) {
	// Skip test if environment is not configured
	env, err := environment.NewEnvironment()
	if err != nil {
		t.Skip("OPENROUTER_API_KEY not set, skipping integration test")
	}

	// Create client with filefinder tool
	config := &openrouter.Config{
		Model: "qwen/qwen3-coder",
	}
	
	client, err := openrouter.NewClient(env, config)
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	type testModel struct {
		chunks           []string
		response         strings.Builder
		completed        bool
		hasError         bool
		error            string
		toolCallMade     bool
		fileFinderOutput []string
		currentCallID    string // track the current tool call ID
		currentArgs      string // accumulate arguments for current call
	}

	model := testModel{}
	done := make(chan bool, 1)

	handler := func(event openrouter.StreamEvent) {
		switch event.Type {
		case openrouter.StreamEventChunk:
			model.chunks = append(model.chunks, event.Content)
			model.response.WriteString(event.Content)
		case openrouter.StreamEventDone:
			// When done, execute any accumulated tool calls
			if model.currentCallID != "" && model.currentArgs != "" {
				t.Logf("Executing accumulated tool call %s with args: %s", model.currentCallID, model.currentArgs)
				tool := filefinder.NewTool()
				result, err := tool.Execute([]byte(model.currentArgs))
				if err != nil {
					model.error = err.Error()
					model.hasError = true
				} else {
					message := result
					// Parse files from the message for verification
					if strings.Contains(message, "- ") {
						lines := strings.Split(message, "\n")
						for _, line := range lines {
							if strings.HasPrefix(line, "- ") {
								file := strings.TrimPrefix(line, "- ")
								model.fileFinderOutput = append(model.fileFinderOutput, file)
							}
						}
					}
					t.Logf("FileFinder executed")
					t.Logf("FileFinder message: %s", message)
				}
			}
			model.completed = true
			done <- true
		case openrouter.StreamEventError:
			model.hasError = true
			model.error = event.Error.Error()
			done <- true
		case openrouter.StreamEventToolCall:
			model.toolCallMade = true
			t.Logf("Received tool call event with %d calls", len(event.ToolCalls))
			// Accumulate tool call arguments (they may come in chunks)
			for _, toolCall := range event.ToolCalls {
				t.Logf("Tool call: ID=%s, Name=%s, Args=%s", toolCall.ID, toolCall.Function.Name, toolCall.Function.Arguments)
				if toolCall.Function.Name == "filefinder" || toolCall.Function.Name == "" {
					// Set the call ID if we get one
					if toolCall.ID != "" {
						model.currentCallID = toolCall.ID
					}
					// Accumulate arguments
					model.currentArgs += toolCall.Function.Arguments
					t.Logf("Accumulated args: %s", model.currentArgs)
				}
			}
		}
	}

	// Ask AI to find all tool_test.go files using the filefinder tool
	userMessage := "I need you to use the filefinder tool to find all files named 'tool_test.go' in the current directory and subdirectories. Use a glob pattern to match these files. You must use the filefinder tool for this."
	
	err = client.SendMessage(userMessage, handler)
	if err != nil {
		t.Fatalf("Failed to send message: %v", err)
	}
	
	// Wait for completion with timeout
	select {
	case <-done:
		// Streaming completed
	case <-time.After(30 * time.Second):
		t.Fatal("Test timed out after 30 seconds")
	}

	// Test assertions
	if model.hasError {
		t.Fatalf("Stream had errors: %s", model.error)
	}
	
	if !model.completed {
		t.Fatal("Stream did not complete properly")
	}

	if !model.toolCallMade {
		t.Fatal("Expected AI to make a filefinder tool call, but none was made")
	}

	// Verify filefinder output contains at least one tool_test.go file
	foundTestFiles := false
	for _, file := range model.fileFinderOutput {
		if strings.Contains(file, "tool_test.go") {
			foundTestFiles = true
			break
		}
	}

	if !foundTestFiles {
		t.Fatalf("Expected filefinder to find at least one tool_test.go file, but found: %v", model.fileFinderOutput)
	}

	// Count how many tool_test.go files were found
	testFileCount := 0
	for _, file := range model.fileFinderOutput {
		if strings.HasSuffix(file, "tool_test.go") {
			testFileCount++
		}
	}

	if testFileCount == 0 {
		t.Fatal("Expected to find at least one tool_test.go file")
	}

	t.Logf("Successfully verified filefinder tool integration:")
	t.Logf("- Tool call made: %v", model.toolCallMade)
	t.Logf("- Found %d tool_test.go files", testFileCount)
	t.Logf("- Files found: %v", model.fileFinderOutput)
	t.Logf("- AI response: %s", model.response.String())
}

func TestFileFinderBasic(t *testing.T) {
	tool := filefinder.NewTool()
	
	if tool.Name() != "filefinder" {
		t.Errorf("Expected name 'filefinder', got '%s'", tool.Name())
	}
	
	def := tool.GetDefinition()
	if def.Function.Name != "filefinder" {
		t.Errorf("Expected function name 'filefinder', got '%s'", def.Function.Name)
	}
	
	if def.Function.Description == "" {
		t.Error("Description should not be empty")
	}
	
	// Test basic execution with glob pattern
	args := map[string]interface{}{
		"pattern": "*.go",
		"glob":    true,
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
	
	t.Logf("FileFinder result: %s", message)
	
	// Basic validation that we got a proper response
	if !strings.Contains(message, "Found") && !strings.Contains(message, "No files found") {
		t.Errorf("Expected message to contain 'Found' or 'No files found', got: %s", message)
	}
}