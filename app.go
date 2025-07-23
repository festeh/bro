package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type App struct {
	messages []string
	input    string
	width    int
	height   int
}

func NewApp() App {
	return App{
		messages: []string{},
		input:    "",
	}
}

func (a App) Init() tea.Cmd {
	return nil
}

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return a, tea.Quit
		case "enter":
			if strings.TrimSpace(a.input) != "" {
				a.messages = append(a.messages, a.input)
				a.input = ""
			}
		case "backspace":
			if len(a.input) > 0 {
				a.input = a.input[:len(a.input)-1]
			}
		default:
			a.input += msg.String()
		}
	}
	return a, nil
}

func (a App) View() string {
	if a.width == 0 || a.height == 0 {
		return "Loading..."
	}

	chatHeight := a.height - 7
	chatWidth := a.width - 2

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
	if len(a.messages) == 0 {
		chatContent = "No messages yet. Start typing below!"
	} else {
		maxMessages := chatHeight - 4
		start := 0
		if len(a.messages) > maxMessages {
			start = len(a.messages) - maxMessages
		}
		for i := start; i < len(a.messages); i++ {
			chatContent += fmt.Sprintf("You: %s\n", a.messages[i])
		}
	}

	chat := chatStyle.Render(chatContent)
	input := inputStyle.Render(fmt.Sprintf("> %s", a.input))
	help := "Press 'q' or Ctrl+C to quit"

	return lipgloss.JoinVertical(lipgloss.Left, chat, input, help)
}
