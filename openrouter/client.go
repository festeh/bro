package openrouter

import (
	"context"
	"fmt"

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

type Config struct {
	Model string
}

type Client struct {
	client *openrouter.Client
	config *Config
}

func NewClient(env *Environment, config *Config) (*Client, error) {
	if env == nil || env.APIKey == "" {
		return nil, fmt.Errorf("valid environment is required")
	}
	if config == nil || config.Model == "" {
		return nil, fmt.Errorf("valid config with model is required")
	}

	return &Client{
		client: openrouter.NewClient(env.APIKey),
		config: config,
	}, nil
}

func (c *Client) SendMessage(userInput string, handler StreamHandler) error {
	messages := []openrouter.ChatCompletionMessage{
		{Role: "user", Content: openrouter.Content{Text: userInput}},
	}

	req := openrouter.ChatCompletionRequest{
		Model:    c.config.Model,
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