package app

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/log"
	"github.com/festeh/bro/config"
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
	messages         []openrouter.Renderable
	input            string
	width            int
	height           int
	currentResponse  string
	pendingToolCalls []openrouter.ToolCall
	isWaiting        bool
	client           *openrouter.Client
	eventChan        chan tea.Msg
	scrollOffset     int // For scrolling through message history
	mode             string
	config           config.Config
	historyIndex     int    // Current position in command history (-1 means not navigating)
	originalInput    string // Store original input when navigating history
}

func NewApp() App {
	appConfig, err := config.InitializeBroDirectory()
	if err != nil {
		log.Error("Failed to initialize bro directory", "error", err)
		os.Exit(1)
	}
	return NewAppWithConfig(*appConfig)
}

func NewAppWithConfig(appConfig config.Config) App {
	env, err := environment.NewEnvironment()
	if err != nil {
		log.Error("Failed to initialize environment", "error", err)
		return App{}
	}

	openrouterConfig := &openrouter.Config{
		// Model: "qwen/qwen3-coder",
		// Model: "anthropic/claude-sonnet-4",
		// Model: "x-ai/grok-4",
		Model: "z-ai/glm-4.5",
	}

	client, err := openrouter.NewClient(env, openrouterConfig)
	if err != nil {
		log.Error("Failed to initialize OpenRouter client", "error", err)
		return App{}
	}

	systemPrompt := GenerateSystemPrompt()
	initialMessages := []openrouter.Renderable{
		openrouter.NewSystemMessage(systemPrompt),
	}

	return App{
		messages:     initialMessages,
		input:        "",
		client:       client,
		eventChan:    make(chan tea.Msg, EVENT_CHAN_BUFFER),
		mode:         "chat",
		config:       appConfig,
		historyIndex: -1,
	}
}

func (a *App) SetMessages(messages []openrouter.Renderable) {
	a.messages = messages
}

func (a App) Init() tea.Cmd {
	return a.listenForEvents()
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

func (a App) streamCompletions() tea.Cmd {
	return func() tea.Msg {
		openrouterMessages := openrouter.ChatMessagesToOpenRouter(a.messages)
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

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
	case tea.KeyMsg:
		if a.mode == "help" {
			if msg.String() == "q" {
				a.mode = "chat"
				return a, nil
			}
			return a, nil
		}
		switch msg.String() {
		case "ctrl+c":
			return a, tea.Quit
		case "ctrl+k":
			_, _, maxLines := a.getChatDimensions()
			totalLines := a.calculateTotalLines()
			if totalLines > maxLines {
				maxScroll := totalLines - maxLines + 1
				if a.scrollOffset < maxScroll {
					a.scrollOffset++
				}
			}
		case "ctrl+j":
			if a.scrollOffset > 0 {
				a.scrollOffset--
			}
		case "up":
			a.navigateHistoryUp()
		case "down":
			a.navigateHistoryDown()
		case "enter":
			if strings.TrimSpace(a.input) != "" && !a.isWaiting && a.client != nil {
				trimmed := strings.TrimSpace(a.input)
				
				// Add command to history
				if err := a.config.History.AddCommand(trimmed); err != nil {
					log.Error("Failed to add command to history", "error", err)
				}
				
				// Log user input to session
				if err := a.config.Session.LogUserInput(trimmed); err != nil {
					log.Error("Failed to log user input to session", "error", err)
				}
				
				// Reset history navigation
				a.historyIndex = -1
				a.originalInput = ""
				
				if a.handleUserCommand(trimmed) {
					return a, nil
				}
				userMsg := openrouter.NewUserMessage(a.input)
				a.messages = append(a.messages, userMsg)
				a.currentResponse = ""
				a.isWaiting = true
				a.scrollOffset = 0

				a.input = ""

				return a, a.streamCompletions()
			}
		case "backspace":
			if len(a.input) > 0 {
				a.input = a.input[:len(a.input)-1]
			}
			// Reset history navigation when typing
			a.historyIndex = -1
			a.originalInput = ""
		default:
			a.input += msg.String()
			// Reset history navigation when typing
			a.historyIndex = -1
			a.originalInput = ""
		}
	case streamChunkMsg:
		a.currentResponse += string(msg)
		return a, a.listenForEvents()
	case streamDoneMsg:
		// Add the AI response first
		if a.currentResponse != "" {
			trimmedResponse := strings.TrimSpace(a.currentResponse)
			a.messages = append(a.messages, openrouter.NewAssistantMessage(trimmedResponse))
			
			// Log AI response with tool calls to session
			toolCallsForLogging := make([]interface{}, len(a.pendingToolCalls))
			for i, toolCall := range a.pendingToolCalls {
				toolCallsForLogging[i] = map[string]interface{}{
					"id":        toolCall.ID,
					"type":      toolCall.Type,
					"function":  toolCall.Function.Name,
					"arguments": toolCall.Function.Arguments,
				}
			}
			if err := a.config.Session.LogAIResponseWithToolCalls(trimmedResponse, toolCallsForLogging); err != nil {
				log.Error("Failed to log AI response with tool calls to session", "error", err)
			}
		}

		// Then execute any pending tool calls in order
		for _, toolCall := range a.pendingToolCalls {
			log.Info("Executing tool call: %v", toolCall)
			// Add tool call message
			toolCallMsg := &openrouter.ToolCallMessage{ToolCall: toolCall}
			a.messages = append(a.messages, toolCallMsg)

			// Execute tool and add response message
			result, err := tools.ExecuteTool(a.client.GetToolRegistry(), toolCall.Function.Name, []byte(toolCall.Function.Arguments))
			toolResponseMsg := &openrouter.ToolResponseMessage{
				ToolCallID: toolCall.ID,
				ToolName:   toolCall.Function.Name,
				Result:     result,
				Error:      err,
			}
			a.messages = append(a.messages, toolResponseMsg)
			
			// Log tool call to session
			if err := a.config.Session.LogToolCall(toolCall.Function.Name, toolCall.Function.Arguments, result); err != nil {
				log.Error("Failed to log tool call to session", "error", err)
			}
		}

		if len(a.pendingToolCalls) > 0 {
			log.Info("Send tool call results")
			go a.streamCompletions()()
		} else {
			log.Info("No tool calls to execute")
		}
		a.resetToBottom()
		return a, a.listenForEvents()
	case streamErrorMsg:
		a.messages = append(a.messages, openrouter.NewAssistantMessage(fmt.Sprintf("Error: %v", msg)))
		a.resetToBottom()
		return a, a.listenForEvents()
	case streamToolCallMsg:
		event := openrouter.StreamEvent(msg)
		for _, newToolCall := range event.ToolCalls {
			if len(a.pendingToolCalls) > 0 && a.pendingToolCalls[len(a.pendingToolCalls)-1].Index == newToolCall.Index {
				// Concatenate to the last tool call
				lastIndex := len(a.pendingToolCalls) - 1
				a.pendingToolCalls[lastIndex].ID += newToolCall.ID
				if a.pendingToolCalls[lastIndex].Type != "" {
					a.pendingToolCalls[lastIndex].Type = newToolCall.Type
				}
				a.pendingToolCalls[lastIndex].Function.Name += newToolCall.Function.Name
				a.pendingToolCalls[lastIndex].Function.Arguments += newToolCall.Function.Arguments
			} else {
				// Add as a new pending tool call
				a.pendingToolCalls = append(a.pendingToolCalls, newToolCall)
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
		currentMsg := openrouter.NewAssistantMessage(a.currentResponse)
		rendered := currentMsg.Render()
		totalLines += a.calculateLinesFromContent(rendered, chatWidth)
	}

	return totalLines
}

func (a *App) resetToBottom() {
	a.currentResponse = ""
	a.pendingToolCalls = nil
	a.isWaiting = false
	a.scrollOffset = 0
}

func (a *App) navigateHistoryUp() {
	
	commands := a.config.History.GetCommands()
	if len(commands) == 0 {
		return
	}
	
	if a.historyIndex == -1 {
		// Starting history navigation, save current input
		a.originalInput = a.input
		a.historyIndex = len(commands) - 1
	} else if a.historyIndex > 0 {
		a.historyIndex--
	}
	
	if a.historyIndex >= 0 && a.historyIndex < len(commands) {
		a.input = commands[a.historyIndex]
	}
}

func (a *App) navigateHistoryDown() {
	if a.historyIndex == -1 {
		return
	}
	
	commands := a.config.History.GetCommands()
	if a.historyIndex < len(commands)-1 {
		a.historyIndex++
		a.input = commands[a.historyIndex]
	} else {
		// Reached end of history, restore original input
		a.historyIndex = -1
		a.input = a.originalInput
		a.originalInput = ""
	}
}

func (a App) getChatDimensions() (chatHeight, chatWidth, maxLines int) {
	chatHeight = a.height - INPUT_HEIGHT
	chatWidth = a.width - CHAT_BORDER_WIDTH
	maxLines = chatHeight - CHAT_PADDING
	return
}

func (a App) View() string {
	if a.mode == "help" {
		helpStyle := lipgloss.NewStyle().Width(a.width).Height(a.height).Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("63")).Align(lipgloss.Center).Padding(2)
		return helpStyle.Render("Bro Help\n\nThis is a basic help screen.\nPress 'q' to return to the chat.")
	}
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
			currentMsg := openrouter.NewAssistantMessage(a.currentResponse)
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
