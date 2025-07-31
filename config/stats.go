package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/charmbracelet/log"
	"github.com/revrost/go-openrouter"
)

type DailyStats struct {
	Date             string  `json:"date"`
	TotalInputTokens int     `json:"total_input_tokens"`
	TotalOutputTokens int    `json:"total_output_tokens"`
	TotalTokens      int     `json:"total_tokens"`
	TotalCost        float64 `json:"total_cost"`
	RequestCount     int     `json:"request_count"`
}

type Stats struct {
	dirPath     string
	currentDate string
	dailyStats  *DailyStats
}

func NewStats() (*Stats, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	broDir := filepath.Join(homeDir, ".bro")
	statsDir := filepath.Join(broDir, "stats")

	// Create stats directory if it doesn't exist
	if err := os.MkdirAll(statsDir, 0755); err != nil {
		return nil, err
	}

	currentDate := time.Now().Format("2006-01-02")
	
	stats := &Stats{
		dirPath:     statsDir,
		currentDate: currentDate,
	}

	// Load or create today's stats
	if err := stats.loadTodaysStats(); err != nil {
		return nil, err
	}

	return stats, nil
}

func (s *Stats) loadTodaysStats() error {
	statsFile := filepath.Join(s.dirPath, fmt.Sprintf("%s.json", s.currentDate))
	
	// Check if today's stats file exists
	if _, err := os.Stat(statsFile); os.IsNotExist(err) {
		// Create new daily stats
		s.dailyStats = &DailyStats{
			Date:             s.currentDate,
			TotalInputTokens: 0,
			TotalOutputTokens: 0,
			TotalTokens:      0,
			TotalCost:        0.0,
			RequestCount:     0,
		}
		return s.saveTodaysStats()
	}

	// Load existing stats
	data, err := os.ReadFile(statsFile)
	if err != nil {
		return err
	}

	var dailyStats DailyStats
	if err := json.Unmarshal(data, &dailyStats); err != nil {
		return err
	}

	s.dailyStats = &dailyStats
	return nil
}

func (s *Stats) saveTodaysStats() error {
	if s.dailyStats == nil {
		return fmt.Errorf("no daily stats to save")
	}

	statsFile := filepath.Join(s.dirPath, fmt.Sprintf("%s.json", s.currentDate))
	
	data, err := json.MarshalIndent(s.dailyStats, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(statsFile, data, 0644)
}

func (s *Stats) AddUsage(usage *openrouter.Usage) error {
	if usage == nil {
		return nil
	}

	// Check if we need to roll over to a new day
	currentDate := time.Now().Format("2006-01-02")
	if currentDate != s.currentDate {
		// Save current stats before rolling over
		if err := s.saveTodaysStats(); err != nil {
			log.Error("Failed to save stats before rollover", "error", err)
		}
		
		// Update to new date and load/create new stats
		s.currentDate = currentDate
		if err := s.loadTodaysStats(); err != nil {
			return err
		}
	}

	// Update stats
	s.dailyStats.TotalInputTokens += usage.PromptTokens
	s.dailyStats.TotalOutputTokens += usage.CompletionTokens
	s.dailyStats.TotalTokens += usage.TotalTokens
	s.dailyStats.TotalCost += usage.Cost
	s.dailyStats.RequestCount++

	// Save updated stats
	return s.saveTodaysStats()
}

func (s *Stats) GetTodaysStats() *DailyStats {
	if s.dailyStats == nil {
		return nil
	}
	
	// Return a copy to prevent external modification
	return &DailyStats{
		Date:             s.dailyStats.Date,
		TotalInputTokens: s.dailyStats.TotalInputTokens,
		TotalOutputTokens: s.dailyStats.TotalOutputTokens,
		TotalTokens:      s.dailyStats.TotalTokens,
		TotalCost:        s.dailyStats.TotalCost,
		RequestCount:     s.dailyStats.RequestCount,
	}
}

func (s *Stats) GetStatsPath() string {
	return s.dirPath
}