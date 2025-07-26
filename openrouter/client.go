package openrouter

import (
	"context"
	"fmt"

	"github.com/revrost/go-openrouter"
)

type StreamEvent struct {
	Type      string
	Content   string
	Error     error
	ToolCalls []ToolCall
}

type ToolCall struct {
	ID       string                 `json:"id"`
	Type     string                 `json:"type"`
	Function ToolCallFunction       `json:"function"`
}

type ToolCallFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

const (
	StreamEventChunk    = "chunk"
	StreamEventDone     = "done"
	StreamEventError    = "error"
	StreamEventToolCall = "tool_call"
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

	tools := []openrouter.Tool{
		{
			Type: openrouter.ToolTypeFunction,
			Function: &openrouter.FunctionDefinition{
				Name:        "bash",
				Description: "Execute a bash command in the terminal and return the output",
				Parameters: map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"command": map[string]interface{}{
							"type":        "string",
							"description": "The bash command to execute",
						},
					},
					"required": []string{"command"},
				},
			},
		},
	}

	req := openrouter.ChatCompletionRequest{
		Model:       c.config.Model,
		Messages:    messages,
		Stream:      true,
		Temperature: 0.5,
		MaxTokens:   10000,
		Tools:       tools,
		Usage: &openrouter.IncludeUsage{
			Include: true,
		},
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

		if len(response.Choices) > 0 {
			choice := response.Choices[0]
			
			if choice.Delta.Content != "" {
				handler(StreamEvent{
					Type:    StreamEventChunk,
					Content: choice.Delta.Content,
				})
			}
			
			if len(choice.Delta.ToolCalls) > 0 {
				var toolCalls []ToolCall
				for _, tc := range choice.Delta.ToolCalls {
					toolCalls = append(toolCalls, ToolCall{
						ID:   tc.ID,
						Type: string(tc.Type),
						Function: ToolCallFunction{
							Name:      tc.Function.Name,
							Arguments: tc.Function.Arguments,
						},
					})
				}
				handler(StreamEvent{
					Type:      StreamEventToolCall,
					ToolCalls: toolCalls,
				})
			}
		}
	}
}

