package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/festeh/bro/openrouter"
)

type Message struct {
	Role    string
	Content string
}

func (m *Message) IsUser() bool {
	return m.Role == "user"
}

type App struct {
	messages        []Message
	input           string
	width           int
	height          int
	currentResponse string
	isWaiting       bool
	client          *openrouter.Client
	eventChan       chan tea.Msg
}

func NewApp() App {
	client, err := openrouter.NewClient()
	if err != nil {
		fmt.Printf("Error initializing OpenRouter client: %v\n", err)
	}

	systemPrompt := GenerateSystemPrompt()
	initialMessages := []Message{
		{Role: "system", Content: systemPrompt},
	}

	return App{
		messages:  initialMessages,
		input:     "",
		client:    client,
		eventChan: make(chan tea.Msg, 100),
	}
}

func (a App) Init() tea.Cmd {
	return tea.Batch(
		func() tea.Msg { return nil },
		a.listenForEvents(),
	)
}

func (a App) listenForEvents() tea.Cmd {
	return func() tea.Msg {
		return <-a.eventChan
	}
}

type streamChunkMsg string
type streamDoneMsg struct{}
type streamErrorMsg error

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
			if strings.TrimSpace(a.input) != "" && !a.isWaiting && a.client != nil {
				userMsg := Message{Role: "user", Content: a.input}
				a.messages = append(a.messages, userMsg)
				a.currentResponse = ""
				a.isWaiting = true

				userInput := a.input
				a.input = ""

				return a, func() tea.Msg {
					err := a.client.SendMessage(userInput, func(event openrouter.StreamEvent) {
						switch event.Type {
						case openrouter.StreamEventChunk:
							a.eventChan <- streamChunkMsg(event.Content)
						case openrouter.StreamEventDone:
							a.eventChan <- streamDoneMsg{}
						case openrouter.StreamEventError:
							a.eventChan <- streamErrorMsg(event.Error)
						}
					})
					if err != nil {
						return streamErrorMsg(err)
					}
					return nil
				}
			}
		case "backspace":
			if len(a.input) > 0 {
				a.input = a.input[:len(a.input)-1]
			}
		default:
			a.input += msg.String()
		}
	case streamChunkMsg:
		a.currentResponse += string(msg)
		return a, a.listenForEvents()
	case streamDoneMsg:
		a.messages = append(a.messages, Message{Role: "assistant", Content: a.currentResponse})
		a.currentResponse = ""
		a.isWaiting = false
		return a, a.listenForEvents()
	case streamErrorMsg:
		a.messages = append(a.messages, Message{Role: "assistant", Content: fmt.Sprintf("Error: %v", msg)})
		a.currentResponse = ""
		a.isWaiting = false
		return a, a.listenForEvents()
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
			prefix := "AI"
			if a.messages[i].IsUser() {
				prefix = "You"
			}
			chatContent += fmt.Sprintf("%s: %s\n", prefix, a.messages[i].Content)
		}

		if a.currentResponse != "" {
			chatContent += fmt.Sprintf("AI: %s", a.currentResponse)
			if a.isWaiting {
				chatContent += "▋"
			}
			chatContent += "\n"
		}
	}

	chat := chatStyle.Render(chatContent)
	input := inputStyle.Render(fmt.Sprintf("> %s", a.input))
	help := "Press 'q' or Ctrl+C to quit"

	return lipgloss.JoinVertical(lipgloss.Left, chat, input, help)
}
