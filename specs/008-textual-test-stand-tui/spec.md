# Agent Test Stand TUI

## What Users Can Do

1. **Chat with the agent**
   User types messages and sees responses in a conversation panel.
   - Works when: Message sent, intent classified, response displayed with metadata
   - Fails when: Show error in conversation with retry option

2. **See live logs**
   User watches server activity in a separate log panel as events happen.
   - Works when: LLM calls, CLI commands, intent classifications stream to log panel
   - Fails when: Errors highlighted in red, full stack traces shown

3. **View current parameters**
   User sees agent configuration at a glance in a sidebar.
   - Works when: Model (with provider), session ID, active state always visible
   - Fails when: N/A (display only)

4. **Switch models**
   User cycles through available models (from all providers) without restarting.
   - Works when: Selection applies to next message, parameters panel updates
   - Fails when: N/A (only valid models in list)

5. **Confirm or decline pending actions**
   User approves or rejects proposed CLI commands with clear buttons.
   - Works when: Pending command highlighted, confirm/decline buttons visible
   - Fails when: N/A (no timeout, waits for user)

## Requirements

### Layout
- [ ] Three-panel layout: conversation (60%), logs (25%), parameters (15%)
- [ ] Conversation shows: user input, intent classification, router decision, agent response
- [ ] Logs written to `/tmp/bro-logs/teststand.log` (consistent with pm2 config)
- [ ] Log panel tails the log file, showing all events as they arrive
- [ ] Log panel auto-scrolls to latest message
- [ ] Parameters panel shows: current model (with provider), session ID, is_active, has_pending

### Interaction
- [ ] Model shown in parameters panel, changed via Ctrl+M
- [ ] Pending commands show confirm/decline buttons in conversation panel (also Y/N keys)
- [ ] On error, show simple retry button in conversation
- [ ] Scrollable history in both conversation and log panels
- [ ] Async-friendly: UI stays responsive during LLM calls

### Keyboard Shortcuts
- [ ] Enter: send message
- [ ] Y: confirm pending action (when visible)
- [ ] N: decline pending action (when visible)
- [ ] Ctrl+M: cycle through all models (merged list from all providers)
- [ ] Ctrl+L: clear all (conversation + logs) / start new session
- [ ] Ctrl+H: show help overlay
- [ ] Ctrl+C: exit app
