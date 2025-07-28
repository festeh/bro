package readfile

func GetDescription() string {
	return `Read the contents of a file from the filesystem using an absolute path. Handles large files by truncating content.

Use this tool when you need to:
- Read configuration files, logs, or documentation
- Examine source code files
- View the contents of text-based files
- Inspect file structure and content
- Debug issues by reading relevant files
- Analyze code, scripts, or data files
- Review file formats and content structure

The tool will return:
- Full file path that was read
- Complete file contents (for files ≤ 200 lines)
- Truncated contents with footer (for files > 200 lines)
- File size and line count information
- Any read errors or access issues

File handling features:
- Automatic truncation for large files (> 200 lines)
- Clear indication when files are truncated
- Preserves file encoding and line endings
- Handles various text file formats
- Provides helpful error messages for access issues

Important considerations:
- Use absolute file paths only (e.g., /home/user/file.txt)
- Tool works best with text-based files
- Binary files may display garbled content
- Large files are automatically truncated for readability
- File must be readable by the current user

Examples of good use cases:
- readfile: {"path": "/home/user/config.json"}
- readfile: {"path": "/var/log/application.log"}
- readfile: {"path": "/etc/nginx/nginx.conf"}
- readfile: {"path": "/home/user/project/src/main.go"}
`
}