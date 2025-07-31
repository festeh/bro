package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/charmbracelet/log"
)

type SessionEntry struct {
	Timestamp time.Time   `json:"timestamp"`
	Type      string      `json:"type"` // "user_input", "ai_response", "tool_call"
	Content   interface{} `json:"content"`
}

type Session struct {
	dirPath     string
	sessionFile *os.File
}

func NewSession() (*Session, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	broDir := filepath.Join(homeDir, ".bro")

	// Create session directory for today
	now := time.Now()
	dayDir := fmt.Sprintf("%02d%s_%d", now.Day(), now.Month().String()[:3], now.Year())
	sessionDir := filepath.Join(broDir, dayDir)

	if err := os.MkdirAll(sessionDir, 0755); err != nil {
		return nil, err
	}

	// Create session file with current time
	sessionFilename := fmt.Sprintf("%02d_%02d.jsonl", now.Hour(), now.Minute())
	sessionPath := filepath.Join(sessionDir, sessionFilename)

	sessionFile, err := os.OpenFile(sessionPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return nil, err
	}

	return &Session{
		dirPath:     sessionDir,
		sessionFile: sessionFile,
	}, nil
}

func (s *Session) LogUserInput(input string) error {
	entry := SessionEntry{
		Timestamp: time.Now(),
		Type:      "user_input",
		Content:   input,
	}
	return s.writeEntry(entry)
}

func (s *Session) LogAIResponse(response string) error {
	entry := SessionEntry{
		Timestamp: time.Now(),
		Type:      "ai_response",
		Content:   response,
	}
	return s.writeEntry(entry)
}

func (s *Session) LogAIResponseWithToolCalls(response string, toolCalls []interface{}) error {
	content := map[string]interface{}{
		"response":   response,
		"tool_calls": toolCalls,
	}

	entry := SessionEntry{
		Timestamp: time.Now(),
		Type:      "ai_response",
		Content:   content,
	}
	return s.writeEntry(entry)
}

func (s *Session) LogToolCall(toolName string, params interface{}, result interface{}) error {
	toolCall := map[string]interface{}{
		"tool_name":  toolName,
		"parameters": params,
		"result":     result,
	}

	entry := SessionEntry{
		Timestamp: time.Now(),
		Type:      "tool_call",
		Content:   toolCall,
	}
	return s.writeEntry(entry)
}

func (s *Session) writeEntry(entry SessionEntry) error {
	if s.sessionFile == nil {
		log.Error("Cannot write session entry: session file not initialized")
		return fmt.Errorf("session file is not initialized")
	}

	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}

	_, err = s.sessionFile.Write(append(data, '\n'))
	if err != nil {
		return err
	}

	return s.sessionFile.Sync()
}

func (s *Session) Close() error {
	if s.sessionFile != nil {
		return s.sessionFile.Close()
	}
	return nil
}
