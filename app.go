package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type Model struct {
	messages []string
	input    string
	cursor   int
	width    int
	height   int
}

func NewModel() Model {
	return Model{
		messages: []string{},
		input:    "",
		cursor:   0,
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
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

func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	chatHeight := m.height - 7
	chatWidth := m.width - 2

	chatStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(1).
		Width(chatWidth).
		Height(chatHeight)

	inputStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("205")).
		Padding(0, 1).
		Width(chatWidth)

	chatContent := ""
	if len(m.messages) == 0 {
		chatContent = "No messages yet. Start typing below!"
	} else {
		maxMessages := chatHeight - 4
		start := 0
		if len(m.messages) > maxMessages {
			start = len(m.messages) - maxMessages
		}
		for i := start; i < len(m.messages); i++ {
			chatContent += fmt.Sprintf("You: %s\n", m.messages[i])
		}
	}

	chat := chatStyle.Render(chatContent)
	input := inputStyle.Render(fmt.Sprintf("> %s", m.input))
	help := "Press 'q' or Ctrl+C to quit"

	return lipgloss.JoinVertical(lipgloss.Left, chat, input, help)
}