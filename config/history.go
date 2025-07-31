package config

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/charmbracelet/log"
)

const (
	HISTORY_SIZE = 100
	HISTORY_FILE = "history.txt"
	INDEX_FILE   = "history_index.txt"
)

type History struct {
	commands []string
	head     int // Index where next command will be written
	size     int // Current number of commands (up to HISTORY_SIZE)
	dirPath  string
}

func NewHistory() (*History, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	dirPath := filepath.Join(homeDir, ".bro")

	h := &History{
		commands: make([]string, HISTORY_SIZE),
		head:     0,
		size:     0,
		dirPath:  dirPath,
	}

	if err := h.load(); err != nil {
		return nil, err
	}

	return h, nil
}

func (h *History) AddCommand(command string) error {
	command = strings.TrimSpace(command)
	if command == "" {
		return nil
	}

	// Don't add duplicate consecutive commands
	if h.size > 0 {
		lastIndex := (h.head - 1 + HISTORY_SIZE) % HISTORY_SIZE
		if h.commands[lastIndex] == command {
			return nil
		}
	}

	h.commands[h.head] = command
	h.head = (h.head + 1) % HISTORY_SIZE

	if h.size < HISTORY_SIZE {
		h.size++
	}

	return h.save()
}

func (h *History) GetCommands() []string {
	if h.size == 0 {
		return nil
	}

	result := make([]string, h.size)

	if h.size < HISTORY_SIZE {
		// Buffer not full yet
		copy(result, h.commands[:h.size])
	} else {
		// Buffer is full, need to handle wrap-around
		copy(result, h.commands[h.head:])
		copy(result[HISTORY_SIZE-h.head:], h.commands[:h.head])
	}

	return result
}

func (h *History) save() error {
	if h.dirPath == "" {
		log.Error("Cannot save history: directory path not initialized")
		return fmt.Errorf("directory path is not initialized")
	}

	historyPath := filepath.Join(h.dirPath, HISTORY_FILE)
	indexPath := filepath.Join(h.dirPath, INDEX_FILE)

	// Save commands array
	file, err := os.Create(historyPath)
	if err != nil {
		return err
	}
	defer file.Close()

	for i, command := range h.commands {
		if i < h.size || h.size == HISTORY_SIZE {
			if _, err := file.WriteString(command + "\n"); err != nil {
				return err
			}
		}
	}

	// Save metadata
	indexFile, err := os.Create(indexPath)
	if err != nil {
		return err
	}
	defer indexFile.Close()

	metadata := strconv.Itoa(h.head) + "\n" + strconv.Itoa(h.size) + "\n"
	_, err = indexFile.WriteString(metadata)
	return err
}

func (h *History) load() error {
	historyPath := filepath.Join(h.dirPath, HISTORY_FILE)
	indexPath := filepath.Join(h.dirPath, INDEX_FILE)

	// Load metadata first
	if _, err := os.Stat(indexPath); os.IsNotExist(err) {
		// No history file exists yet
		return nil
	}

	indexFile, err := os.Open(indexPath)
	if err != nil {
		return err
	}
	defer indexFile.Close()

	scanner := bufio.NewScanner(indexFile)

	if scanner.Scan() {
		if h.head, err = strconv.Atoi(strings.TrimSpace(scanner.Text())); err != nil {
			return err
		}
	}

	if scanner.Scan() {
		if h.size, err = strconv.Atoi(strings.TrimSpace(scanner.Text())); err != nil {
			return err
		}
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	// Load commands
	historyFile, err := os.Open(historyPath)
	if err != nil {
		return err
	}
	defer historyFile.Close()

	scanner = bufio.NewScanner(historyFile)
	i := 0
	for scanner.Scan() && i < HISTORY_SIZE {
		h.commands[i] = strings.TrimSpace(scanner.Text())
		i++
	}

	return scanner.Err()
}
