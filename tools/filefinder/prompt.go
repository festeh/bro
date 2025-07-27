package filefinder

func GetDescription() string {
	return `Find files and directories using patterns or regex. Uses the fd tool internally for fast searching.

Use this tool when you need to:
- Find files by name pattern or regex
- Locate specific file types (files, directories, symlinks, etc.)
- Search for files across directory structures
- Filter files by glob patterns
- Quickly locate source code files
- Find configuration or data files
- Search for files matching specific naming conventions

The tool will return:
- Pattern used for search
- List of matching file paths
- Count of files found
- Any search errors

Pattern types:
- Regex (default): Use regular expressions for regular expression matching
- Glob: Set "glob": true for shell-style patterns like *.go, test*.js

Important considerations:
- Use glob patterns for simple wildcard matching (*.txt, **/*.go)
- Use regex for complex pattern matching
- Type filter helps narrow results (file, directory, symlink, executable, empty)
- Searches are recursive by default

Examples of good use cases:
- filefinder: {"pattern": "*.go", "glob": true, "type": "file"}
- filefinder: {"pattern": "test.*\\.js$", "type": "file"}
- filefinder: {"pattern": "config", "type": "directory"}
- filefinder: {"pattern": "README.*", "glob": true}
`
}
