package grep

func GetDescription() string {
	return `Search for text patterns within files using ripgrep (rg). Fast and powerful text searching with context.

Use this tool when you need to:
- Search for specific text or patterns in files
- Find occurrences of functions, variables, or strings in code
- Search across multiple files with regex patterns
- Get context lines around matches for better understanding
- Locate specific log entries or configuration values
- Find TODOs, FIXMEs, or other annotations in code
- Search for imports, dependencies, or API usage

The tool will return:
- Pattern used for search
- File paths containing matches
- Line numbers and content of matches
- Context lines (if requested)
- Total count of matches found

Search features:
- Full regex support for complex patterns
- Case-sensitive and case-insensitive search
- Context lines before and after matches
- Path filtering and exclusions
- Recursive directory searching

Important considerations:
- Use specific patterns to avoid too many results
- Add context lines to understand match surroundings
- Specify paths to narrow search scope
- Use proper regex escaping for special characters

Examples of good use cases:
- grep: {"pattern": "func main", "path": ".", "context": 3}
- grep: {"pattern": "TODO|FIXME", "path": "src/", "context": 1}
- grep: {"pattern": "import.*react", "path": ".", "context": 0}
- grep: {"pattern": "error", "path": "logs/", "context": 2}
`
}