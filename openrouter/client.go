package openrouter

import (
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/charmbracelet/log"
	"github.com/festeh/bro/environment"
	"github.com/festeh/bro/tools"
	"github.com/festeh/bro/tools/bash"
	"github.com/festeh/bro/tools/fileedit"
	"github.com/festeh/bro/tools/filefinder"
	"github.com/festeh/bro/tools/grep"
	"github.com/festeh/bro/tools/readfile"
	"github.com/revrost/go-openrouter"
)

type StreamEvent struct {
	Type      string
	Content   string
	Error     error
	ToolCalls []ToolCall
	Usage     *openrouter.Usage
}

type ToolCall struct {
	Index    int              `json:"index"`
	ID       string           `json:"id"`
	Type     string           `json:"type"`
	Function ToolCallFunction `json:"function"`
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
	StreamEventUsage    = "usage"
)

type StreamHandler func(StreamEvent)

type Config struct {
	Model        string
	ToolRegistry *tools.Registry
}

type Client struct {
	client *openrouter.Client
	config *Config
}

func NewClient(env *environment.Environment, config *Config) (*Client, error) {
	if env == nil || env.APIKey == "" {
		return nil, fmt.Errorf("valid environment is required")
	}
	if config == nil || config.Model == "" {
		return nil, fmt.Errorf("valid config with model is required")
	}

	// Create default tool registry with tools if none provided
	if config.ToolRegistry == nil {
		config.ToolRegistry = tools.NewRegistry()
		config.ToolRegistry.Register(bash.NewTool())
		config.ToolRegistry.Register(fileedit.NewTool())
		config.ToolRegistry.Register(filefinder.NewTool())
		config.ToolRegistry.Register(grep.NewTool())
		config.ToolRegistry.Register(readfile.NewTool())
	}

	return &Client{
		client: openrouter.NewClient(env.APIKey),
		config: config,
	}, nil
}

// SetToolRegistry updates the tool registry for this client
func (c *Client) SetToolRegistry(registry *tools.Registry) {
	c.config.ToolRegistry = registry
}

// GetToolRegistry returns the current tool registry
func (c *Client) GetToolRegistry() *tools.Registry {
	return c.config.ToolRegistry
}

// SetModel updates the model for this client
func (c *Client) SetModel(model string) {
	c.config.Model = model
}

// GetModel returns the current model
func (c *Client) GetModel() string {
	return c.config.Model
}

func (c *Client) SendMessages(messages []openrouter.ChatCompletionMessage, handler StreamHandler) error {

	// Get tools from the client's registry
	tools := c.config.ToolRegistry.GetDefinitions()

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
		StreamOptions: &openrouter.StreamOptions{
			IncludeUsage: true,
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
			if errors.Is(err, io.EOF) {
				handler(StreamEvent{Type: StreamEventDone})
				return
			}
			handler(StreamEvent{Type: StreamEventError, Error: err})
			return
		}

		// Handle usage information if present
		if response.Usage != nil {
			log.Info("Received usage information", "prompt_tokens", response.Usage.PromptTokens, "completion_tokens", response.Usage.CompletionTokens, "total_cost", response.Usage.Cost)
			handler(StreamEvent{
				Type:  StreamEventUsage,
				Usage: response.Usage,
			})
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
				log.Info("Received tool call delta", "count", len(choice.Delta.ToolCalls))
				var toolCalls []ToolCall
				for i, tc := range choice.Delta.ToolCalls {
					log.Info("Tool call delta", "index", i, "id", tc.ID, "type", tc.Type, "function_name", tc.Function.Name, "arguments", tc.Function.Arguments)
					index := 0
					if tc.Index != nil {
						index = *tc.Index
					}
					toolCalls = append(toolCalls, ToolCall{
						Index: index,
						ID:    tc.ID,
						Type:  string(tc.Type),
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
