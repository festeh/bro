<script>
  import Chat from './lib/Chat.svelte'
  import TTS from './lib/TTS.svelte'
  import { onMount } from 'svelte';

  let activeTab = $state('chat');
  let mounted = $state(false);

  const tabs = [
    { id: 'chat', label: 'CHAT', icon: '>', description: 'AI conversation' },
    { id: 'tts', label: 'TTS', icon: '~', description: 'Text synthesis' },
    { id: 'asr', label: 'ASR', icon: '<', description: 'Voice recognition' },
  ];

  onMount(() => {
    setTimeout(() => mounted = true, 100);
  });
</script>

<div class="console" class:mounted>
  <!-- Ambient glow effects -->
  <div class="ambient-glow glow-1"></div>
  <div class="ambient-glow glow-2"></div>

  <!-- Header -->
  <header class="header">
    <div class="logo-section">
      <div class="logo-mark">
        <span class="logo-bracket">[</span>
        <span class="logo-text">BRO</span>
        <span class="logo-bracket">]</span>
      </div>
      <div class="logo-tagline">
        <span class="tagline-prefix">AI_</span>
        <span class="tagline-text">DEBUG_CONSOLE</span>
        <span class="cursor"></span>
      </div>
    </div>

    <div class="header-status">
      <div class="status-item">
        <span class="status-dot online"></span>
        <span class="status-label">SYSTEM ONLINE</span>
      </div>
      <div class="version-badge">v0.1.0</div>
    </div>
  </header>

  <!-- Navigation -->
  <nav class="nav">
    {#each tabs as tab, i}
      <button
        class="nav-tab"
        class:active={activeTab === tab.id}
        onclick={() => activeTab = tab.id}
        style="--delay: {i * 0.1}s"
      >
        <span class="tab-icon">{tab.icon}</span>
        <span class="tab-label">{tab.label}</span>
        <span class="tab-desc">{tab.description}</span>
        {#if activeTab === tab.id}
          <div class="tab-indicator"></div>
        {/if}
      </button>
    {/each}
    <div class="nav-line"></div>
  </nav>

  <!-- Main Content -->
  <main class="main">
    <div class="content-frame">
      {#if activeTab === 'chat'}
        <div class="panel" style="--panel-delay: 0s">
          <Chat />
        </div>
      {:else if activeTab === 'tts'}
        <div class="panel" style="--panel-delay: 0s">
          <TTS />
        </div>
      {:else if activeTab === 'asr'}
        <div class="panel coming-soon" style="--panel-delay: 0s">
          <div class="coming-soon-content">
            <div class="coming-soon-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/>
                <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
                <line x1="12" y1="19" x2="12" y2="22"/>
              </svg>
            </div>
            <h2 class="coming-soon-title">ASR MODULE</h2>
            <p class="coming-soon-subtitle">Voice recognition system initializing...</p>
            <div class="progress-bar">
              <div class="progress-fill"></div>
            </div>
            <span class="status-code">STATUS: PENDING_IMPLEMENTATION</span>
          </div>
        </div>
      {/if}
    </div>
  </main>

  <!-- Footer -->
  <footer class="footer">
    <div class="footer-left">
      <span class="footer-label">SESSION</span>
      <code class="session-id">{crypto.randomUUID().slice(0, 8).toUpperCase()}</code>
    </div>
    <div class="footer-center">
      <span class="footer-dot"></span>
      <span class="footer-text">SECURE CONNECTION</span>
    </div>
    <div class="footer-right">
      <span class="timestamp">{new Date().toISOString().replace('T', ' ').slice(0, 19)}</span>
    </div>
  </footer>
</div>

<style>
  .console {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
    position: relative;
    overflow: hidden;
    opacity: 0;
    transition: opacity 0.5s ease;
  }

  .console.mounted {
    opacity: 1;
  }

  /* Ambient glow effects */
  .ambient-glow {
    position: fixed;
    pointer-events: none;
    border-radius: 50%;
    filter: blur(100px);
    opacity: 0.4;
    z-index: -1;
  }

  .glow-1 {
    width: 600px;
    height: 600px;
    background: radial-gradient(circle, var(--cyan-glow), transparent 70%);
    top: -200px;
    left: -100px;
    animation: float-glow 20s ease-in-out infinite;
  }

  .glow-2 {
    width: 500px;
    height: 500px;
    background: radial-gradient(circle, var(--pink-glow), transparent 70%);
    bottom: -150px;
    right: -100px;
    animation: float-glow 25s ease-in-out infinite reverse;
  }

  @keyframes float-glow {
    0%, 100% { transform: translate(0, 0); }
    33% { transform: translate(30px, -20px); }
    66% { transform: translate(-20px, 30px); }
  }

  /* Header */
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: var(--space-lg) var(--space-xl);
    background: linear-gradient(180deg, var(--carbon) 0%, transparent 100%);
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    animation: slide-down 0.6s var(--ease-out) forwards;
  }

  @keyframes slide-down {
    from {
      opacity: 0;
      transform: translateY(-20px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .logo-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-xs);
  }

  .logo-mark {
    font-family: var(--font-display);
    font-size: 1.8rem;
    letter-spacing: 0.1em;
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .logo-bracket {
    color: var(--cyan);
    text-shadow: 0 0 20px var(--cyan-glow);
  }

  .logo-text {
    color: var(--text-primary);
    background: linear-gradient(135deg, var(--text-primary), var(--cyan));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }

  .logo-tagline {
    font-size: 0.7rem;
    font-weight: 300;
    letter-spacing: 0.3em;
    color: var(--text-muted);
    display: flex;
    align-items: center;
  }

  .tagline-prefix {
    color: var(--pink);
  }

  .cursor {
    display: inline-block;
    width: 6px;
    height: 12px;
    background: var(--cyan);
    margin-left: 4px;
    animation: typing-cursor 1s step-end infinite;
  }

  .header-status {
    display: flex;
    align-items: center;
    gap: var(--space-lg);
  }

  .status-item {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    font-size: 0.7rem;
    letter-spacing: 0.15em;
    color: var(--text-secondary);
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--green);
    box-shadow: 0 0 10px var(--green-glow);
    animation: status-pulse 2s infinite;
  }

  .status-dot.online {
    color: var(--green);
  }

  .version-badge {
    font-size: 0.65rem;
    padding: var(--space-xs) var(--space-sm);
    background: var(--slate);
    border-radius: var(--radius-sm);
    color: var(--text-muted);
    letter-spacing: 0.1em;
  }

  /* Navigation */
  .nav {
    display: flex;
    align-items: stretch;
    padding: 0 var(--space-xl);
    position: relative;
    gap: var(--space-xs);
  }

  .nav-line {
    position: absolute;
    bottom: 0;
    left: var(--space-xl);
    right: var(--space-xl);
    height: 1px;
    background: linear-gradient(90deg, transparent, var(--steel), transparent);
  }

  .nav-tab {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    padding: var(--space-md) var(--space-lg);
    color: var(--text-muted);
    font-size: 0.8rem;
    letter-spacing: 0.2em;
    opacity: 0;
    animation: fade-slide-up 0.5s var(--ease-out) forwards;
    animation-delay: var(--delay);
  }

  @keyframes fade-slide-up {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .nav-tab:hover {
    color: var(--text-secondary);
  }

  .nav-tab.active {
    color: var(--cyan);
  }

  .tab-icon {
    font-size: 1.2rem;
    font-weight: 700;
    margin-bottom: 2px;
    font-family: var(--font-mono);
  }

  .tab-label {
    font-weight: 600;
  }

  .tab-desc {
    font-size: 0.6rem;
    letter-spacing: 0.1em;
    color: var(--text-muted);
    margin-top: 2px;
  }

  .nav-tab.active .tab-desc {
    color: var(--cyan-dim);
  }

  .tab-indicator {
    position: absolute;
    bottom: -1px;
    left: 0;
    right: 0;
    height: 2px;
    background: var(--cyan);
    box-shadow: 0 0 10px var(--cyan), 0 0 20px var(--cyan-glow);
    animation: indicator-grow 0.3s var(--ease-out);
  }

  @keyframes indicator-grow {
    from { transform: scaleX(0); }
    to { transform: scaleX(1); }
  }

  /* Main Content */
  .main {
    flex: 1;
    padding: var(--space-xl);
    display: flex;
  }

  .content-frame {
    flex: 1;
    background: var(--obsidian);
    border: 1px solid rgba(255, 255, 255, 0.04);
    border-radius: var(--radius-lg);
    overflow: hidden;
    box-shadow: var(--shadow-float), inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .panel {
    height: 100%;
    animation: panel-enter 0.4s var(--ease-out);
    animation-delay: var(--panel-delay);
  }

  @keyframes panel-enter {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  /* Coming Soon Panel */
  .coming-soon {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 500px;
  }

  .coming-soon-content {
    text-align: center;
    animation: float 3s ease-in-out infinite;
  }

  @keyframes float {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-10px); }
  }

  .coming-soon-icon {
    width: 80px;
    height: 80px;
    margin: 0 auto var(--space-lg);
    color: var(--pink);
    opacity: 0.5;
    animation: pulse-glow 2s ease-in-out infinite;
  }

  .coming-soon-icon svg {
    width: 100%;
    height: 100%;
  }

  .coming-soon-title {
    font-family: var(--font-display);
    font-size: 1.5rem;
    letter-spacing: 0.3em;
    color: var(--text-primary);
    margin-bottom: var(--space-sm);
  }

  .coming-soon-subtitle {
    font-size: 0.85rem;
    color: var(--text-muted);
    margin-bottom: var(--space-lg);
  }

  .progress-bar {
    width: 200px;
    height: 3px;
    background: var(--slate);
    border-radius: 2px;
    margin: 0 auto var(--space-md);
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    width: 30%;
    background: linear-gradient(90deg, var(--pink), var(--amber));
    border-radius: 2px;
    animation: progress-pulse 2s ease-in-out infinite;
  }

  @keyframes progress-pulse {
    0%, 100% { width: 30%; opacity: 1; }
    50% { width: 50%; opacity: 0.7; }
  }

  .status-code {
    font-size: 0.65rem;
    letter-spacing: 0.2em;
    color: var(--amber);
    opacity: 0.6;
  }

  /* Footer */
  .footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: var(--space-md) var(--space-xl);
    background: linear-gradient(0deg, var(--carbon) 0%, transparent 100%);
    border-top: 1px solid rgba(255, 255, 255, 0.03);
    font-size: 0.65rem;
    letter-spacing: 0.1em;
    color: var(--text-muted);
  }

  .footer-left, .footer-right {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
  }

  .footer-center {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
  }

  .footer-label {
    color: var(--text-muted);
  }

  .session-id {
    font-size: 0.7rem;
    padding: 2px 6px;
    background: var(--slate);
    border-radius: 2px;
    color: var(--cyan);
  }

  .footer-dot {
    width: 6px;
    height: 6px;
    background: var(--green);
    border-radius: 50%;
    animation: status-pulse 3s infinite;
  }

  .footer-text {
    color: var(--text-secondary);
  }

  .timestamp {
    font-variant-numeric: tabular-nums;
    color: var(--text-muted);
  }
</style>
