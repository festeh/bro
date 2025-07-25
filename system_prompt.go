package main

import (
	"fmt"
	"os"
	"runtime"
	"time"
)

func GenerateSystemPrompt() string {
	currentTime := time.Now().Format("2006-01-02 15:04:05")
	currentDir, err := os.Getwd()
	if err != nil {
		currentDir = "unknown"
	}
	
	osInfo := fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)
	
	return fmt.Sprintf(`Current time: %s
OS: %s
Working directory: %s
You are helpful cli assistant`, currentTime, osInfo, currentDir)
}