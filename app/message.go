package app

import "github.com/revrost/go-openrouter"

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

func ChatMessagesToOpenRouter(messages []*ChatMessage) []openrouter.ChatCompletionMessage {
	var result []openrouter.ChatCompletionMessage
	for _, msg := range messages {
		result = append(result, openrouter.ChatCompletionMessage(*msg))
	}
	return result
}