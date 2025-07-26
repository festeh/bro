package openrouter

import (
	"strings"
	"testing"
	"time"
)

func TestClientStreaming(t *testing.T) {
	// Skip test if environment is not configured
	env, err := NewEnvironment()
	if err != nil {
		t.Skip("OPENROUTER_API_KEY not set, skipping integration test")
	}

	config := &Config{
		Model: "openai/gpt-3.5-turbo",
	}
	
	client, err := NewClient(env, config)
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	type testModel struct {
		chunks    []string
		response  strings.Builder
		completed bool
		hasError  bool
		error     string
	}

	model := testModel{}
	done := make(chan bool, 1)

	handler := func(event StreamEvent) {
		switch event.Type {
		case StreamEventChunk:
			model.chunks = append(model.chunks, event.Content)
			model.response.WriteString(event.Content)
		case StreamEventDone:
			model.completed = true
			done <- true
		case StreamEventError:
			model.hasError = true
			model.error = event.Error.Error()
			done <- true
		}
	}

	// Execute the streaming request
	err = client.SendMessage("hey how are you", handler)
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
	
	if len(model.chunks) <= 1 {
		t.Fatalf("Expected more than 1 chunk, got %d chunks", len(model.chunks))
	}
	
	finalResponse := model.response.String()
	if strings.TrimSpace(finalResponse) == "" {
		t.Fatal("Response is empty")
	}
	
	t.Logf("Successfully received %d chunks", len(model.chunks))
	t.Logf("Final response: %s", finalResponse)
}
