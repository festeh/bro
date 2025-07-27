package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/festeh/bro/app"
)

func main() {
	myApp := app.NewApp()

	// Create initial message with numbers 1-30 separated by newlines
	var numbers []string
	for i := 1; i <= 10; i++ {
		numbers = append(numbers, fmt.Sprintf("%d\n\n", i))
	}
	numbersContent := strings.Join(numbers, "")

	initialMessages := []app.Message{
		{Role: app.RoleUser, Content: numbersContent},
	}

	myApp.SetMessages(initialMessages)

	p := tea.NewProgram(myApp)

	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v", err)
	}
}
