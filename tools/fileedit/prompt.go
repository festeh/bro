package fileedit

func GetDescription() string {
	return `Edit files by replacing exact string matches. Ensures string uniqueness to avoid ambiguous replacements.

Use this tool when you need to:
- Replace specific text, code, or configuration values in files
- Make precise edits to source code files
- Update configuration parameters or settings
- Fix bugs by replacing incorrect code snippets
- Refactor code by renaming variables or functions
- Update documentation or comments
- Modify data files with specific content changes

The tool will:
- Verify the target string exists exactly once in the file
- Perform the replacement if string is unique
- Overwrite the original file with changes
- Return success confirmation or error details
- Preserve file permissions and encoding

Safety features:
- Requires exact string match (case-sensitive)
- Fails if string appears multiple times (ambiguity protection)
- Fails if string doesn't exist in file
- Validates file access and permissions
- Creates backup behavior through error reporting

Important considerations:
- Use absolute file paths for clarity
- String matching is exact and case-sensitive
- Whitespace and special characters must match exactly
- Tool overwrites the original file (ensure you have backups)
- Multi-line strings are supported with proper escaping
- Empty replacement string is allowed (deletion)

Examples of good use cases:
- fileedit: {"path": "/home/user/config.json", "old_string": "\"debug\": false", "new_string": "\"debug\": true"}
- fileedit: {"path": "/etc/nginx/nginx.conf", "old_string": "worker_processes 1;", "new_string": "worker_processes auto;"}
- fileedit: {"path": "/home/user/app.py", "old_string": "def old_function():", "new_string": "def new_function():"}
- fileedit: {"path": "/home/user/README.md", "old_string": "Version 1.0", "new_string": "Version 2.0"}
`
}