package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/log"
	"github.com/festeh/bro/app"
	"github.com/festeh/bro/openrouter"
)

func main() {
	myApp := app.NewApp()

	// Create initial message with numbers 1-30 separated by newlines
	var numbers []string
	for i := 1; i <= 30; i++ {
		numbers = append(numbers, fmt.Sprintf("%d", i))
	}
	numbersContent := strings.Join(numbers, "\n")

	initialMessages := []openrouter.Renderable{
		openrouter.NewSystemMessage(app.GenerateSystemPrompt()),
		openrouter.NewUserMessage(numbersContent),
	}

	myApp.SetMessages(initialMessages)

	p := tea.NewProgram(myApp)

	if _, err := p.Run(); err != nil {
		log.Error("Failed to run program", "error", err)
	}
}
