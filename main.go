package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type model struct {
	messages []string
	input    string
	cursor   int
}

func initialModel() model {
	return model{
		messages: []string{},
		input:    "",
		cursor:   0,
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "enter":
			if strings.TrimSpace(m.input) != "" {
				m.messages = append(m.messages, m.input)
				m.input = ""
			}
		case "backspace":
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}
		default:
			m.input += msg.String()
		}
	}
	return m, nil
}

func (m model) View() string {
	var s strings.Builder

	chatStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(1).
		Width(80).
		Height(20)

	inputStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("205")).
		Padding(0, 1).
		Width(80)

	chatContent := ""
	if len(m.messages) == 0 {
		chatContent = "No messages yet. Start typing below!"
	} else {
		maxMessages := 18
		start := 0
		if len(m.messages) > maxMessages {
			start = len(m.messages) - maxMessages
		}
		for i := start; i < len(m.messages); i++ {
			chatContent += fmt.Sprintf("You: %s\n", m.messages[i])
		}
	}

	s.WriteString(chatStyle.Render(chatContent))
	s.WriteString("\n")
	s.WriteString(inputStyle.Render(fmt.Sprintf("> %s", m.input)))
	s.WriteString("\n\nPress 'q' or Ctrl+C to quit")

	return s.String()
}

func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v", err)
	}
}