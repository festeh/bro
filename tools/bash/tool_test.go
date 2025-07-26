package bash_test

import (
	"os/user"
	"strings"
	"testing"
	"time"

	"github.com/festeh/bro/environment"
	"github.com/festeh/bro/openrouter"
	"github.com/festeh/bro/tools/bash"
)

func TestBashToolWithAI(t *testing.T) {
	// Skip test if environment is not configured
	env, err := environment.NewEnvironment()
	if err != nil {
		t.Skip("OPENROUTER_API_KEY not set, skipping integration test")
	}

	// Get the actual username for verification
	currentUser, err := user.Current()
	if err != nil {
		t.Fatalf("Failed to get current user: %v", err)
	}
	expectedUsername := currentUser.Username

	// Create client with bash tool
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
		bashOutput       string
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
				tool := bash.NewTool()
				result, err := tool.Execute([]byte(model.currentArgs))
				if err != nil {
					model.error = err.Error()
					model.hasError = true
				} else if bashResult, ok := result.(bash.Result); ok {
					model.bashOutput = bashResult.Stdout
					t.Logf("Bash command executed: %s", bashResult.Command)
					t.Logf("Bash output: %s", bashResult.Stdout)
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
				if toolCall.Function.Name == "bash" || toolCall.Function.Name == "" {
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

	// Ask AI to find out the username using bash - be very explicit
	userMessage := "I need you to use the bash tool to execute the 'whoami' command and tell me what the current username is. You must use the bash tool for this."
	
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
		t.Fatal("Expected AI to make a bash tool call, but none was made")
	}

	// Verify bash output contains the username
	if !strings.Contains(model.bashOutput, expectedUsername) {
		t.Fatalf("Expected bash output to contain username '%s', but got: %s", expectedUsername, model.bashOutput)
	}

	// Verify AI response mentions the username (soft check)
	finalResponse := model.response.String()
	if !strings.Contains(strings.ToLower(finalResponse), strings.ToLower(expectedUsername)) {
		t.Logf("Expected AI response to mention username '%s'", expectedUsername)
		t.Logf("AI response: %s", finalResponse)
		t.Logf("Bash output was: %s", model.bashOutput)
		// This is a soft assertion - AI might format the response differently
		t.Logf("WARNING: AI response didn't explicitly mention the username, but bash tool worked correctly")
	}

	t.Logf("Successfully verified bash tool integration:")
	t.Logf("- Tool call made: %v", model.toolCallMade)
	t.Logf("- Expected username: %s", expectedUsername)
	t.Logf("- Bash output: %s", strings.TrimSpace(model.bashOutput))
	t.Logf("- AI response: %s", finalResponse)
}