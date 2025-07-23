package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/revrost/go-openrouter"
)

type Message struct {
	Role    string
	Content string
	IsBot   bool
}

type streamChunkMsg string
type streamDoneMsg struct{}
type streamErrorMsg error

type App struct {
	messages        []Message
	input           string
	width           int
	height          int
	currentResponse string
	isWaiting       bool
}

func NewApp() App {
	return App{
		messages: []Message{},
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
			if strings.TrimSpace(a.input) != "" && !a.isWaiting {
				userMsg := Message{Role: "user", Content: a.input, IsBot: false}
				a.messages = append(a.messages, userMsg)
				a.currentResponse = ""
				a.isWaiting = true
				cmd := a.sendToOpenRouter(a.input)
				a.input = ""
				return a, cmd
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
	case streamDoneMsg:
		a.messages = append(a.messages, Message{Role: "assistant", Content: a.currentResponse, IsBot: true})
		a.currentResponse = ""
		a.isWaiting = false
	case streamErrorMsg:
		a.messages = append(a.messages, Message{Role: "assistant", Content: fmt.Sprintf("Error: %v", msg), IsBot: true})
		a.currentResponse = ""
		a.isWaiting = false
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
			prefix := "You"
			if a.messages[i].IsBot {
				prefix = "AI"
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

func (a App) sendToOpenRouter(userInput string) tea.Cmd {
	return func() tea.Msg {
		apiKey := os.Getenv("OPENROUTER_API_KEY")
		if apiKey == "" {
			return streamErrorMsg(fmt.Errorf("OPENROUTER_API_KEY environment variable not set"))
		}

		client := openrouter.NewClient(apiKey)
		
		messages := []openrouter.ChatCompletionMessage{
			{Role: "user", Content: openrouter.Content{Text: userInput}},
		}

		req := openrouter.ChatCompletionRequest{
			Model:    "openai/gpt-3.5-turbo",
			Messages: messages,
			Stream:   true,
		}

		stream, err := client.CreateChatCompletionStream(context.Background(), req)
		if err != nil {
			return streamErrorMsg(err)
		}

		return tea.Batch(a.readFromStream(stream))
	}
}

func (a App) readFromStream(stream *openrouter.ChatCompletionStream) tea.Cmd {
	return func() tea.Msg {
		response, err := stream.Recv()
		if err != nil {
			stream.Close()
			if err.Error() == "EOF" {
				return streamDoneMsg{}
			}
			return streamErrorMsg(err)
		}

		if len(response.Choices) > 0 && response.Choices[0].Delta.Content != "" {
			return tea.Batch(
				func() tea.Msg { return streamChunkMsg(response.Choices[0].Delta.Content) },
				a.readFromStream(stream),
			)
		}

		return a.readFromStream(stream)
	}
}
