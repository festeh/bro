package bash

func GetDescription() string {
	return `Execute a bash command in the terminal and return the output.

Use this tool when you need to:
- Run system commands (ls, cat, grep, etc.)
- Execute scripts or programs
- Check file system information
- Install packages or manage dependencies
- Perform system administration tasks
- Test or debug code
- Process files or data with command-line tools

The tool will return:
- Command executed
- Standard output (stdout)
- Standard error (stderr) 
- Exit code (0 for success, non-zero for failure)
- Any execution errors

Important considerations:
- Commands run in the current working directory
- Never use rm command - always move to /tmp directory
- Use proper quoting for commands with spaces or special characters

Examples of good use cases:
- bash: {"command": "ls -la"}
- bash: {"command": "cat package.json"}
- bash: {"command": "grep -r 'function' src/"}
- bash: {"command": "git status"}
- bash: {"command": "npm test"}
`
}
