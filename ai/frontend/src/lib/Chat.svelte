<script>
  import { onMount, onDestroy } from 'svelte';
  import { log } from './logger.js';

  const providers = [
    { id: 'groq', name: 'GROQ', model: 'Llama 3.3', color: 'var(--cyan)' },
    { id: 'openrouter', name: 'OPENROUTER', model: 'Llama 3.3', color: 'var(--pink)' },
    { id: 'gemini', name: 'GEMINI', model: '2.0 Flash', color: 'var(--amber)' },
    { id: 'chutes', name: 'CHUTES', model: 'DeepSeek V3', color: 'var(--green)' },
  ];

  let provider = $state('groq');
  let threadId = $state(crypto.randomUUID());
  let messages = $state([]);
  let input = $state('');
  let ws = $state(null);
  let connected = $state(false);
  let streaming = $state(false);
  let currentResponse = $state('');
  let messagesContainer = $state(null);

  function connect() {
    log.ws.info('connecting', { threadId, host: location.host });
    ws = new WebSocket(`ws://${location.host}/ws/${threadId}`);

    ws.onopen = () => {
      connected = true;
      log.ws.info('connected', { threadId });
    };

    ws.onclose = () => {
      connected = false;
      log.ws.info('disconnected', { threadId });
    };

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);

      if (data.type === 'history') {
        messages = data.messages.map(m => ({
          role: m.role === 'human' ? 'user' : m.role,
          content: m.content
        }));
        log.chat.debug('history_loaded', { count: messages.length });
      } else if (data.type === 'chunk') {
        currentResponse += data.content;
        messages = [...messages.slice(0, -1), { role: 'assistant', content: currentResponse }];
        scrollToBottom();
      } else if (data.type === 'done') {
        streaming = false;
        log.chat.info('response_complete', { length: currentResponse.length });
        currentResponse = '';
      } else if (data.type === 'error') {
        log.chat.error('server_error', { message: data.message });
        streaming = false;
      }
    };
  }

  function scrollToBottom() {
    if (messagesContainer) {
      setTimeout(() => {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }, 10);
    }
  }

  function send() {
    if (!input.trim() || !connected || streaming) return;

    const content = input.trim();
    input = '';

    log.chat.info('sending_message', { provider, length: content.length });

    messages = [...messages, { role: 'user', content }];
    messages = [...messages, { role: 'assistant', content: '' }];
    currentResponse = '';
    streaming = true;
    scrollToBottom();

    ws.send(JSON.stringify({ type: 'message', content, provider }));
  }

  function newThread() {
    log.chat.info('new_thread');
    if (ws) ws.close();
    threadId = crypto.randomUUID();
    messages = [];
    connect();
  }

  function handleKeydown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  function getProviderColor() {
    return providers.find(p => p.id === provider)?.color || 'var(--cyan)';
  }

  onMount(() => {
    connect();
  });

  onDestroy(() => {
    if (ws) ws.close();
  });
</script>

<div class="chat-container">
  <!-- Header Bar -->
  <div class="chat-header">
    <div class="provider-section">
      <span class="provider-label">PROVIDER</span>
      <div class="provider-selector">
        {#each providers as p}
          <button
            class="provider-btn"
            class:active={provider === p.id}
            style="--provider-color: {p.color}"
            onclick={() => provider = p.id}
          >
            <span class="provider-name">{p.name}</span>
            <span class="provider-model">{p.model}</span>
          </button>
        {/each}
      </div>
    </div>

    <div class="header-actions">
      <button class="action-btn new-chat" onclick={newThread}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M12 5v14M5 12h14"/>
        </svg>
        <span>NEW</span>
      </button>

      <div class="connection-status" class:online={connected}>
        <span class="status-indicator"></span>
        <span class="status-text">{connected ? 'LIVE' : 'OFFLINE'}</span>
      </div>
    </div>
  </div>

  <!-- Messages Area -->
  <div class="messages-area" bind:this={messagesContainer}>
    {#if messages.length === 0}
      <div class="empty-state">
        <div class="empty-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
          </svg>
        </div>
        <h3 class="empty-title">READY FOR INPUT</h3>
        <p class="empty-subtitle">Initialize conversation with the AI system</p>
      </div>
    {:else}
      {#each messages as msg, i}
        <div
          class="message"
          class:user={msg.role === 'user'}
          class:assistant={msg.role === 'assistant'}
          style="--msg-delay: {Math.min(i * 0.05, 0.3)}s"
        >
          <div class="message-header">
            <span class="message-role">{msg.role === 'user' ? 'YOU' : 'AI'}</span>
            {#if msg.role === 'assistant' && streaming && i === messages.length - 1}
              <span class="streaming-indicator">
                <span class="dot"></span>
                <span class="dot"></span>
                <span class="dot"></span>
              </span>
            {/if}
          </div>
          <div class="message-content">
            {msg.content}
            {#if msg.role === 'assistant' && streaming && i === messages.length - 1 && msg.content}
              <span class="typing-cursor"></span>
            {/if}
          </div>
        </div>
      {/each}
    {/if}
  </div>

  <!-- Input Area -->
  <div class="input-area">
    <div class="input-wrapper" style="--accent: {getProviderColor()}">
      <textarea
        bind:value={input}
        onkeydown={handleKeydown}
        placeholder="Enter command..."
        disabled={!connected || streaming}
        rows="1"
      ></textarea>
      <button
        class="send-btn"
        onclick={send}
        disabled={!connected || streaming || !input.trim()}
      >
        {#if streaming}
          <div class="sending-animation">
            <span></span>
            <span></span>
            <span></span>
          </div>
        {:else}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>
          </svg>
        {/if}
      </button>
    </div>
    <div class="input-hint">
      <kbd>Enter</kbd> to send · <kbd>Shift+Enter</kbd> for new line
    </div>
  </div>
</div>

<style>
  .chat-container {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 600px;
  }

  /* Header */
  .chat-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: var(--space-md) var(--space-lg);
    background: var(--carbon);
    border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  }

  .provider-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
  }

  .provider-label {
    font-size: 0.6rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
  }

  .provider-selector {
    display: flex;
    gap: var(--space-xs);
  }

  .provider-btn {
    display: flex;
    flex-direction: column;
    padding: var(--space-sm) var(--space-md);
    background: var(--slate);
    border-radius: var(--radius-sm);
    color: var(--text-muted);
    font-size: 0.65rem;
    letter-spacing: 0.1em;
    border: 1px solid transparent;
  }

  .provider-btn:hover {
    background: var(--steel);
    color: var(--text-secondary);
  }

  .provider-btn.active {
    background: transparent;
    border-color: var(--provider-color);
    color: var(--provider-color);
    box-shadow: 0 0 15px color-mix(in srgb, var(--provider-color) 20%, transparent);
  }

  .provider-name {
    font-weight: 600;
  }

  .provider-model {
    font-size: 0.55rem;
    opacity: 0.7;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: var(--space-md);
  }

  .action-btn {
    display: flex;
    align-items: center;
    gap: var(--space-xs);
    padding: var(--space-sm) var(--space-md);
    background: var(--slate);
    border-radius: var(--radius-sm);
    color: var(--text-secondary);
    font-size: 0.7rem;
    letter-spacing: 0.1em;
  }

  .action-btn:hover {
    background: var(--steel);
    color: var(--text-primary);
  }

  .action-btn svg {
    width: 14px;
    height: 14px;
  }

  .connection-status {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    padding: var(--space-sm) var(--space-md);
    background: rgba(255, 51, 102, 0.1);
    border-radius: var(--radius-sm);
    font-size: 0.65rem;
    letter-spacing: 0.15em;
    color: var(--red);
  }

  .connection-status.online {
    background: rgba(0, 255, 136, 0.1);
    color: var(--green);
  }

  .status-indicator {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
    animation: status-pulse 2s infinite;
  }

  /* Messages */
  .messages-area {
    flex: 1;
    overflow-y: auto;
    padding: var(--space-lg);
    display: flex;
    flex-direction: column;
    gap: var(--space-md);
  }

  .empty-state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    color: var(--text-muted);
    animation: fade-in 0.5s ease;
  }

  .empty-icon {
    width: 60px;
    height: 60px;
    margin-bottom: var(--space-lg);
    opacity: 0.3;
  }

  .empty-icon svg {
    width: 100%;
    height: 100%;
  }

  .empty-title {
    font-size: 0.9rem;
    letter-spacing: 0.3em;
    color: var(--text-secondary);
    margin-bottom: var(--space-sm);
  }

  .empty-subtitle {
    font-size: 0.75rem;
    opacity: 0.6;
  }

  .message {
    max-width: 85%;
    animation: message-enter 0.3s var(--ease-out);
    animation-delay: var(--msg-delay);
    animation-fill-mode: backwards;
  }

  @keyframes message-enter {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .message.user {
    align-self: flex-end;
  }

  .message.assistant {
    align-self: flex-start;
  }

  .message-header {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    margin-bottom: var(--space-xs);
  }

  .message-role {
    font-size: 0.6rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
  }

  .message.user .message-role {
    color: var(--cyan-dim);
  }

  .message.assistant .message-role {
    color: var(--pink-dim);
  }

  .streaming-indicator {
    display: flex;
    gap: 3px;
  }

  .streaming-indicator .dot {
    width: 4px;
    height: 4px;
    background: var(--pink);
    border-radius: 50%;
    animation: dot-pulse 1.4s ease-in-out infinite;
  }

  .streaming-indicator .dot:nth-child(2) {
    animation-delay: 0.2s;
  }

  .streaming-indicator .dot:nth-child(3) {
    animation-delay: 0.4s;
  }

  @keyframes dot-pulse {
    0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
    40% { opacity: 1; transform: scale(1); }
  }

  .message-content {
    padding: var(--space-md) var(--space-lg);
    border-radius: var(--radius-md);
    font-size: 0.9rem;
    line-height: 1.6;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .message.user .message-content {
    background: linear-gradient(135deg, var(--cyan-dim), var(--cyan));
    color: var(--void);
    border-bottom-right-radius: var(--radius-sm);
  }

  .message.assistant .message-content {
    background: var(--carbon);
    border: 1px solid rgba(255, 255, 255, 0.05);
    color: var(--text-primary);
    border-bottom-left-radius: var(--radius-sm);
  }

  .typing-cursor {
    display: inline-block;
    width: 2px;
    height: 1em;
    background: var(--pink);
    margin-left: 2px;
    vertical-align: text-bottom;
    animation: typing-cursor 0.8s step-end infinite;
  }

  /* Input Area */
  .input-area {
    padding: var(--space-lg);
    background: linear-gradient(0deg, var(--carbon) 0%, transparent 100%);
    border-top: 1px solid rgba(255, 255, 255, 0.04);
  }

  .input-wrapper {
    display: flex;
    gap: var(--space-sm);
    padding: var(--space-sm);
    background: var(--obsidian);
    border: 1px solid var(--slate);
    border-radius: var(--radius-md);
    transition: all 0.25s var(--ease-out);
  }

  .input-wrapper:focus-within {
    border-color: var(--accent);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 15%, transparent),
                0 0 20px color-mix(in srgb, var(--accent) 10%, transparent);
  }

  .input-wrapper textarea {
    flex: 1;
    padding: var(--space-md);
    background: transparent;
    border: none;
    color: var(--text-primary);
    font-size: 0.9rem;
    resize: none;
    min-height: 24px;
    max-height: 120px;
  }

  .input-wrapper textarea::placeholder {
    color: var(--text-muted);
  }

  .input-wrapper textarea:focus {
    outline: none;
    box-shadow: none;
  }

  .send-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    background: var(--cyan);
    border-radius: var(--radius-sm);
    color: var(--void);
    flex-shrink: 0;
  }

  .send-btn:hover:not(:disabled) {
    background: var(--cyan-dim);
    transform: scale(1.05);
  }

  .send-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .send-btn svg {
    width: 18px;
    height: 18px;
  }

  .sending-animation {
    display: flex;
    gap: 3px;
  }

  .sending-animation span {
    width: 4px;
    height: 4px;
    background: var(--void);
    border-radius: 50%;
    animation: sending-dots 1s ease-in-out infinite;
  }

  .sending-animation span:nth-child(2) {
    animation-delay: 0.15s;
  }

  .sending-animation span:nth-child(3) {
    animation-delay: 0.3s;
  }

  @keyframes sending-dots {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-4px); }
  }

  .input-hint {
    display: flex;
    justify-content: center;
    gap: var(--space-md);
    margin-top: var(--space-sm);
    font-size: 0.65rem;
    color: var(--text-muted);
    letter-spacing: 0.05em;
  }

  .input-hint kbd {
    padding: 2px 6px;
    background: var(--slate);
    border-radius: 3px;
    font-family: var(--font-mono);
    font-size: 0.6rem;
  }
</style>
