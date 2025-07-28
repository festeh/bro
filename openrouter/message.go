package openrouter

import (
	"fmt"
	"github.com/revrost/go-openrouter"
)

type Renderable interface {
	Render() string
	IsUser() bool
}

type ChatMessage openrouter.ChatCompletionMessage

func (m *ChatMessage) IsUser() bool {
	return m.Role == "user"
}

func (m *ChatMessage) Render() string {
	prefix := "AI"
	if m.IsUser() {
		prefix = "You"
	}
	return prefix + ": " + m.Content.Text
}

type ToolCallMessage struct {
	ToolCall ToolCall
}

func (m *ToolCallMessage) IsUser() bool {
	return false
}

func (m *ToolCallMessage) Render() string {
	return fmt.Sprintf("  🔧 Executing %s: %s", m.ToolCall.Function.Name, m.ToolCall.Function.Arguments)
}

type ToolResponseMessage struct {
	ToolCallID string
	ToolName   string
	Result     string
	Error      error
}

func (m *ToolResponseMessage) IsUser() bool {
	return false
}

func (m *ToolResponseMessage) Render() string {
	if m.Error != nil {
		return fmt.Sprintf("  ❌ Tool execution error: %s", m.Error.Error())
	}

	return "  " + m.Result
}

func NewUserMessage(content string) *ChatMessage {
	return &ChatMessage{
		Role:    "user",
		Content: openrouter.Content{Text: content},
	}
}

func NewAssistantMessage(content string) *ChatMessage {
	return &ChatMessage{
		Role:    "assistant",
		Content: openrouter.Content{Text: content},
	}
}

func NewSystemMessage(content string) *ChatMessage {
	return &ChatMessage{
		Role:    "system",
		Content: openrouter.Content{Text: content},
	}
}

func ChatMessagesToOpenRouter(messages []Renderable) []openrouter.ChatCompletionMessage {
	var result []openrouter.ChatCompletionMessage
	for _, msg := range messages {
		switch m := msg.(type) {
		case *ChatMessage:
			// Regular chat messages (user/assistant/system)
			result = append(result, openrouter.ChatCompletionMessage(*m))
		case *ToolCallMessage:
			// Assistant message with tool calls
			toolCall := openrouter.ToolCall{
				ID:   m.ToolCall.ID,
				Type: openrouter.ToolType(m.ToolCall.Type),
				Function: openrouter.FunctionCall{
					Name:      m.ToolCall.Function.Name,
					Arguments: m.ToolCall.Function.Arguments,
				},
			}
			result = append(result, openrouter.ChatCompletionMessage{
				Role:      "assistant",
				ToolCalls: []openrouter.ToolCall{toolCall},
			})
		case *ToolResponseMessage:
			// Tool response message
			var content string
			if m.Error != nil {
				content = fmt.Sprintf("Error: %s", m.Error.Error())
			} else {
				content = m.Result
			}
			result = append(result, openrouter.ToolMessage(m.ToolCallID, content))
		}
	}
	return result
}
