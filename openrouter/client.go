package openrouter

import (
	"context"
	"fmt"
	"os"

	"github.com/revrost/go-openrouter"
)

type StreamEvent struct {
	Type    string
	Content string
	Error   error
}

const (
	StreamEventChunk = "chunk"
	StreamEventDone  = "done"
	StreamEventError = "error"
)

type StreamHandler func(StreamEvent)

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

func (c *Client) SendMessage(userInput string, handler StreamHandler) error {
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
		handler(StreamEvent{Type: StreamEventError, Error: err})
		return err
	}

	go c.readFromStream(stream, handler)
	return nil
}

func (c *Client) readFromStream(stream *openrouter.ChatCompletionStream, handler StreamHandler) {
	defer stream.Close()
	
	for {
		response, err := stream.Recv()
		if err != nil {
			if err.Error() == "EOF" {
				handler(StreamEvent{Type: StreamEventDone})
				return
			}
			handler(StreamEvent{Type: StreamEventError, Error: err})
			return
		}

		if len(response.Choices) > 0 && response.Choices[0].Delta.Content != "" {
			handler(StreamEvent{
				Type:    StreamEventChunk,
				Content: response.Choices[0].Delta.Content,
			})
		}
	}
}