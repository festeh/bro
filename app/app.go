package app

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/charmbracelet/log"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/festeh/bro/environment"
	"github.com/festeh/bro/openrouter"
	"github.com/festeh/bro/tools"
)

const (
	INPUT_HEIGHT       = 7
	CHAT_PADDING       = 0
	CHAT_BORDER_WIDTH  = 2
	EVENT_CHAN_BUFFER  = 100
	BORDER_COLOR_CHAT  = "62"
	BORDER_COLOR_INPUT = "205"
	CURSOR_CHAR        = "▋"
)

type App struct {
	messages        []Message
	input           string
	width           int
	height          int
	currentResponse string
	isWaiting       bool
	client          *openrouter.Client
	eventChan       chan tea.Msg
	scrollOffset    int // For scrolling through message history
}


// ExecuteTool executes a tool by name with the given arguments using the provided registry
func ExecuteTool(registry *tools.Registry, name string, args json.RawMessage) (interface{}, error) {
	tool, exists := registry.Get(name)
	if !exists {
		return nil, fmt.Errorf("tool '%s' not found", name)
	}

	return tool.Execute(args)
}

func NewApp() App {
	env, err := environment.NewEnvironment()
	if err != nil {
		log.Error("Failed to initialize environment", "error", err)
		return App{}
	}

	config := &openrouter.Config{
		Model: "qwen/qwen3-coder",
	}

	client, err := openrouter.NewClient(env, config)
	if err != nil {
		log.Error("Failed to initialize OpenRouter client", "error", err)
		return App{}
	}

	systemPrompt := GenerateSystemPrompt()
	initialMessages := []Message{
		{Role: RoleSystem, Content: systemPrompt},
	}

	return App{
		messages:  initialMessages,
		input:     "",
		client:    client,
		eventChan: make(chan tea.Msg, EVENT_CHAN_BUFFER),
	}
}

func (a *App) SetMessages(messages []Message) {
	a.messages = messages
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
type streamToolCallMsg openrouter.StreamEvent

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return a, tea.Quit
		case "up":
			_, _, maxLines := a.getChatDimensions()
			totalLines := a.calculateTotalLines()
			if totalLines > maxLines {
				maxScroll := totalLines - maxLines + 1
				if a.scrollOffset < maxScroll {
					a.scrollOffset++
				}
			}
		case "down":
			if a.scrollOffset > 0 {
				a.scrollOffset--
			}
		case "enter":
			if strings.TrimSpace(a.input) != "" && !a.isWaiting && a.client != nil {
				userMsg := Message{Role: RoleUser, Content: a.input}
				a.messages = append(a.messages, userMsg)
				a.currentResponse = ""
				a.isWaiting = true
				a.scrollOffset = 0

				a.input = ""

				return a, func() tea.Msg {
					openrouterMessages := MessagesToOpenRouter(a.messages)
					err := a.client.SendMessages(openrouterMessages, func(event openrouter.StreamEvent) {
						switch event.Type {
						case openrouter.StreamEventChunk:
							a.eventChan <- streamChunkMsg(event.Content)
						case openrouter.StreamEventDone:
							a.eventChan <- streamDoneMsg{}
						case openrouter.StreamEventError:
							a.eventChan <- streamErrorMsg(event.Error)
						case openrouter.StreamEventToolCall:
							a.eventChan <- streamToolCallMsg(event)
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
		a.messages = append(a.messages, Message{Role: RoleAssistant, Content: a.currentResponse})
		a.resetToBottom()
		return a, a.listenForEvents()
	case streamErrorMsg:
		a.messages = append(a.messages, Message{Role: RoleAssistant, Content: fmt.Sprintf("Error: %v", msg)})
		a.resetToBottom()
		return a, a.listenForEvents()
	case streamToolCallMsg:
		event := openrouter.StreamEvent(msg)
		for _, toolCall := range event.ToolCalls {
			a.currentResponse += fmt.Sprintf("\n🔧 Executing %s: %s\n", toolCall.Function.Name, toolCall.Function.Arguments)

			result, err := ExecuteTool(a.client.GetToolRegistry(), toolCall.Function.Name, []byte(toolCall.Function.Arguments))
			if err != nil {
				a.currentResponse += fmt.Sprintf("Tool execution error: %s\n", err.Error())
			} else {
				// All tools now return formatted assistant messages
				if message, ok := result.(string); ok {
					a.currentResponse += message + "\n"
				} else {
					// Fallback for any tools that still return structured data
					a.currentResponse += fmt.Sprintf("Result: %+v\n", result)
				}
			}
		}
		return a, a.listenForEvents()
	}
	return a, nil
}

func (a App) calculateLinesFromContent(content string, chatWidth int) int {
	lines := strings.Split(content, "\n")
	totalLines := 0
	for _, line := range lines {
		if len(line) == 0 {
			totalLines += 1 // Empty lines take 1 screen line
		} else {
			totalLines += (len(line) + chatWidth - 1) / chatWidth // Ceiling division
		}
	}
	return totalLines
}

func (a App) calculateTotalLines() int {
	_, chatWidth, _ := a.getChatDimensions()
	if chatWidth <= 0 {
		chatWidth = 80 // Default width
	}

	totalLines := 0
	for _, msg := range a.messages {
		rendered := msg.Render()
		totalLines += a.calculateLinesFromContent(rendered, chatWidth)
	}

	if a.currentResponse != "" {
		currentMsg := &Message{Role: RoleAssistant, Content: a.currentResponse}
		rendered := currentMsg.Render()
		totalLines += a.calculateLinesFromContent(rendered, chatWidth)
	}

	return totalLines
}

func (a *App) resetToBottom() {
	a.currentResponse = ""
	a.isWaiting = false
	a.scrollOffset = 0
}

func (a App) getChatDimensions() (chatHeight, chatWidth, maxLines int) {
	chatHeight = a.height - INPUT_HEIGHT
	chatWidth = a.width - CHAT_BORDER_WIDTH
	maxLines = chatHeight - CHAT_PADDING
	return
}

func (a App) View() string {
	if a.width == 0 || a.height == 0 {
		return "Loading..."
	}

	chatHeight, chatWidth, maxLines := a.getChatDimensions()

	chatStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(BORDER_COLOR_CHAT)).
		Width(chatWidth).
		Height(chatHeight)

	inputStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(BORDER_COLOR_INPUT)).
		Width(chatWidth)

	chatContent := ""
	if len(a.messages) == 0 {
		chatContent = "No messages yet. Start typing below!"
	} else {

		// Build all content lines
		var allLines []string
		for _, msg := range a.messages {
			rendered := msg.Render()
			lines := strings.Split(rendered, "\n")
			allLines = append(allLines, lines...)
		}

		// Add current response if present
		if a.currentResponse != "" {
			currentMsg := &Message{Role: RoleAssistant, Content: a.currentResponse}
			rendered := currentMsg.Render()
			lines := strings.Split(rendered, "\n")
			for i, line := range lines {
				content := line
				if a.isWaiting && i == len(lines)-1 {
					content += CURSOR_CHAR
				}
				allLines = append(allLines, content)
			}
		}

		// First wrap all lines to get complete wrapped content
		var allWrappedLines []string
		for _, line := range allLines {
			if len(line) <= chatWidth {
				allWrappedLines = append(allWrappedLines, line)
			} else {
				// Wrap long lines
				for len(line) > chatWidth {
					allWrappedLines = append(allWrappedLines, line[:chatWidth])
					line = line[chatWidth:]
				}
				if len(line) > 0 {
					allWrappedLines = append(allWrappedLines, line)
				}
			}
		}

		// Apply scrolling based on wrapped line count
		totalLines := len(allWrappedLines)
		start := 0
		if totalLines > maxLines {
			start = totalLines - maxLines - a.scrollOffset
		}

		if start < 0 {
			start = 0
		}
		if start >= totalLines {
			start = totalLines - 1
		}

		end := start + maxLines
		if end > totalLines {
			end = totalLines
		}

		var visibleLines []string
		for i := start; i < end; i++ {
			visibleLines = append(visibleLines, allWrappedLines[i])
		}

		chatContent = strings.Join(visibleLines, "\n")
	}

	chat := chatStyle.Render(chatContent)
	input := inputStyle.Render(fmt.Sprintf("> %s", a.input))
	help := ""

	// Debug info
	totalLines := a.calculateTotalLines()
	debug := fmt.Sprintf("Debug: offset=%d, totalLines=%d, maxLines=%d",
		a.scrollOffset, totalLines, maxLines)

	return lipgloss.JoinVertical(lipgloss.Left, chat, input, help, debug)
}
