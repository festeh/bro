package openrouter

import (
	"fmt"
	"strings"
	"github.com/charmbracelet/lipgloss"
	"github.com/revrost/go-openrouter"
)

var (
	redStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF0000"))
	purpleStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#9B59B6"))
)

type Renderable interface {
	Render() string
}

type AIChatMessage struct {
	openrouter.ChatCompletionMessage
	ModelName string
}

func (m *AIChatMessage) Render() string {
	prefix := "(AI)"
	if m.ModelName != "" {
		// Extract the model name after the last slash for cleaner display
		parts := strings.Split(m.ModelName, "/")
		if len(parts) > 1 {
			prefix = purpleStyle.Render("(" + parts[len(parts)-1] + ")")
		} else {
			prefix = purpleStyle.Render("(" + m.ModelName + ")")
		}
	}
	return prefix + ": " + m.Content.Text
}

type UserChatMessage struct {
	openrouter.ChatCompletionMessage
}

func (m *UserChatMessage) Render() string {
	return "You: " + m.Content.Text
}

type ToolCallMessage struct {
	ToolCall ToolCall
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


func (m *ToolResponseMessage) Render() string {
	if m.Error != nil {
		return fmt.Sprintf("  ❌ Tool execution error: %s", m.Error.Error())
	}

	return "  " + m.Result
}

func NewUserMessage(content string) *UserChatMessage {
	return &UserChatMessage{
		ChatCompletionMessage: openrouter.ChatCompletionMessage{
			Role:    "user",
			Content: openrouter.Content{Text: content},
		},
	}
}

func NewAssistantMessage(content string, modelName string) *AIChatMessage {
	return &AIChatMessage{
		ChatCompletionMessage: openrouter.ChatCompletionMessage{
			Role:    "assistant",
			Content: openrouter.Content{Text: content},
		},
		ModelName: modelName,
	}
}

func NewSystemMessage(content string) *AIChatMessage {
	return &AIChatMessage{
		ChatCompletionMessage: openrouter.ChatCompletionMessage{
			Role:    "system",
			Content: openrouter.Content{Text: content},
		},
		ModelName: "",
	}
}

type CommandResponseMessage struct {
	content string
}


func (m *CommandResponseMessage) Render() string {
	return m.content
}

func NewCommandResponseMessage(content string) *CommandResponseMessage {
	return &CommandResponseMessage{
		content: content,
	}
}

type CommandErrorResponseMessage struct {
	content string
}


func (m *CommandErrorResponseMessage) Render() string {
	return m.content
}

func NewCommandErrorResponseMessage(content string) *CommandResponseMessage {
	return &CommandResponseMessage{
		content: redStyle.Render(content),
	}
}

func ChatMessagesToOpenRouter(messages []Renderable) []openrouter.ChatCompletionMessage {
	var result []openrouter.ChatCompletionMessage
	for _, msg := range messages {
		switch m := msg.(type) {
		case *AIChatMessage:
			// AI chat messages (assistant/system)
			result = append(result, m.ChatCompletionMessage)
		case *UserChatMessage:
			// User chat messages
			result = append(result, m.ChatCompletionMessage)
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
		case *CommandResponseMessage:
			// Command response messages are not sent to the AI - skip them
			continue
		}
	}
	return result
}
