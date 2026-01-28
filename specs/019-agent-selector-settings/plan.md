# Plan: Agent Selector Settings

## Summary

Add a persistent setting to control which agents are enabled. Store as **excluded** agents, display as **enabled** in UI.

**Default behavior**: On cold start (fresh install), excluded set is empty, so all checkmarks are active. Users disable agents by unchecking, which adds them to the excluded set.

## Tech Stack

- Language: Dart (Flutter) + Python
- Framework: Flutter (app), livekit-agents (backend)
- Storage: SharedPreferences (Flutter) for persistence
- Sync: LiveKit metadata (Flutter → Python)

## Structure

Changes span both Flutter and Python:

```
app/lib/
├── services/
│   ├── settings_service.dart    # Add excluded agents getter/setter
│   └── livekit_service.dart     # Add excluded agents to metadata
├── pages/
│   └── home_page.dart           # Add agent selector to mobile settings sheet
└── widgets/
    └── app_sidebar.dart         # Add agent selector to desktop sidebar

agent/
└── voice_agent.py               # Read excluded_agents, skip routing to disabled agents
```

## Available Agents

Currently there's one selectable agent:
- **TaskAgent** - handles task management (add, list, complete tasks)

ChatAgent is the main agent and always runs. TaskAgent is a sub-agent invoked via intent classification.

## Approach

### 1. Settings Storage (settings_service.dart)

Add excluded agents as a `Set<String>` stored in SharedPreferences as a JSON-encoded list.

```dart
// Key
static const String _keyExcludedAgents = 'excludedAgents';

// Getter - returns set of excluded agent names (empty on cold start)
Set<String> get excludedAgents

// Setter - persists excluded agents
Future<void> setExcludedAgents(Set<String> excluded)

// Helper - check if agent is enabled (not in excluded set)
// Returns true on cold start since excluded set is empty
bool isAgentEnabled(String agentName)
```

### 2. LiveKit Metadata Sync (livekit_service.dart)

Add `excluded_agents` field to metadata sent to Python backend.

```dart
// Add field
Set<String> _excludedAgents = {};

// Add to _updateMetadata()
'excluded_agents': _excludedAgents.toList(),

// Add setter
void setExcludedAgents(Set<String> excluded)
```

### 3. Desktop UI (app_sidebar.dart)

Add agent selector below TTS toggle. Each agent shows icon + name + checkbox.

```dart
_AgentSelector(
  enabledAgents: {'task'},  // Derived from excludedAgents
  onChanged: onEnabledAgentsChanged,
)
```

Widget shows each agent as a row with:
- Checkbox (leading)
- Icon in rounded container (same style as message bubbles)
- Agent name

Use `Icons.task_alt` for TaskAgent (same as `_getIntentIcon('task_management')` in chat_page.dart).

### 4. Mobile UI (home_page.dart → _SettingsSheet)

Add same agent selector component to the mobile settings sheet. Reuse the same icon and layout pattern.

### 5. Python Backend (voice_agent.py)

Read `excluded_agents` from metadata in `AgentSettings`:

```python
@dataclass
class AgentSettings:
    # ... existing fields ...
    excluded_agents: list[str] = field(default_factory=list)
```

In `_process_input()`, check before routing to TaskAgent:

```python
if classification.intent == Intent.TASK_MANAGEMENT:
    if "task" in self._settings.excluded_agents:
        # Fall through to default LLM response
        return Ok(None)
    return await self._route_to_task_agent(text)
```

## Agent Registry

Define agent metadata in a list within the UI widget (no need for separate file with only one agent):

```dart
const _availableAgents = [
  (id: 'task', name: 'Task Manager', icon: Icons.task_alt),
];
```

| Agent | ID | Icon | Description |
|-------|-----|------|-------------|
| TaskAgent | `task` | `Icons.task_alt` | Voice-controlled task management |

Icon matches `_getIntentIcon('task_management')` in `chat_page.dart` for consistency with message bubbles.

## Data Flow

1. User toggles agent in UI
2. `SettingsService.setExcludedAgents()` persists to SharedPreferences
3. `LiveKitService.setExcludedAgents()` updates metadata
4. Python reads `excluded_agents` from participant metadata
5. `ChatAgent._process_input()` checks before routing

## UI Design

### Desktop (Sidebar)
```
Agents
┌────────────────────────────┐
│ [✓] [📋] Task Manager      │
└────────────────────────────┘
```

### Mobile (Settings Sheet)
```
Agents
[✓] [📋] Task Manager
```

Each agent row shows:
- Checkbox (checked = enabled, unchecked = disabled)
- Icon in rounded container (same style as message bubbles)
- Agent display name

**Checkbox logic**: `checked = !excludedAgents.contains(agentId)`. On cold start, excluded set is empty, so all boxes are checked.

Icons match `_getIntentIcon()` from `chat_page.dart`:
- TaskAgent: `Icons.task_alt` (matches `task_management` intent)

## Risks

- **Settings sync timing**: Metadata update might not reach agent immediately. Mitigate by sending on every setting change (existing pattern).
- **Unknown agent IDs**: If stored ID doesn't match known agents, ignore it. Don't crash.

## Implementation Order

1. `settings_service.dart` - Add persistence
2. `livekit_service.dart` - Add metadata sync
3. `voice_agent.py` - Read setting and apply to routing
4. `app_sidebar.dart` - Add desktop UI
5. `home_page.dart` - Add mobile UI
