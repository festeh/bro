package app

import "github.com/revrost/go-openrouter"

type Role int

const (
	RoleUser Role = iota
	RoleAssistant
	RoleSystem
)

func (r Role) String() string {
	switch r {
	case RoleUser:
		return "user"
	case RoleAssistant:
		return "assistant"
	case RoleSystem:
		return "system"
	default:
		return "unknown"
	}
}

type Message struct {
	Role    Role
	Content string
}

func (m *Message) IsUser() bool {
	return m.Role == RoleUser
}

func (m *Message) Render() string {
	prefix := "AI"
	if m.IsUser() {
		prefix = "You"
	}
	return prefix + ": " + m.Content
}

func (m *Message) ToOpenRouterMessage() openrouter.ChatCompletionMessage {
	return openrouter.ChatCompletionMessage{
		Role:    m.Role.String(),
		Content: openrouter.Content{Text: m.Content},
	}
}

func MessagesToOpenRouter(messages []Message) []openrouter.ChatCompletionMessage {
	var result []openrouter.ChatCompletionMessage
	for _, msg := range messages {
		result = append(result, msg.ToOpenRouterMessage())
	}
	return result
}