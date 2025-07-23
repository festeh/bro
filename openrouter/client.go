package openrouter

import (
	"context"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/revrost/go-openrouter"
)

type StreamChunkMsg string
type StreamDoneMsg struct{}
type StreamErrorMsg error

type Client struct {
	client *openrouter.Client
}

func NewClient() (*Client, error) {
	apiKey := os.Getenv("OPENROUTER_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPENROUTER_API_KEY environment variable not set")
	}

	return &Client{
		client: openrouter.NewClient(apiKey),
	}, nil
}

func (c *Client) SendMessage(userInput string) tea.Cmd {
	return func() tea.Msg {
		messages := []openrouter.ChatCompletionMessage{
			{Role: "user", Content: openrouter.Content{Text: userInput}},
		}

		req := openrouter.ChatCompletionRequest{
			Model:    "openai/gpt-3.5-turbo",
			Messages: messages,
			Stream:   true,
		}

		stream, err := c.client.CreateChatCompletionStream(context.Background(), req)
		if err != nil {
			return StreamErrorMsg(err)
		}

		return tea.Batch(c.readFromStream(stream))
	}
}

func (c *Client) readFromStream(stream *openrouter.ChatCompletionStream) tea.Cmd {
	return func() tea.Msg {
		response, err := stream.Recv()
		if err != nil {
			stream.Close()
			if err.Error() == "EOF" {
				return StreamDoneMsg{}
			}
			return StreamErrorMsg(err)
		}

		if len(response.Choices) > 0 && response.Choices[0].Delta.Content != "" {
			return tea.Batch(
				func() tea.Msg { return StreamChunkMsg(response.Choices[0].Delta.Content) },
				c.readFromStream(stream),
			)
		}

		return c.readFromStream(stream)
	}
}