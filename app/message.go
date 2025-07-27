package app

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