<script>
  import { onMount } from 'svelte';
  import { log } from './logger.js';

  let text = $state("Hello, this is a test of the text to speech system.");
  let voice = $state("en-US-AriaNeural");
  let voices = $state([]);
  let loading = $state(false);
  let audioUrl = $state(null);
  let isPlaying = $state(false);
  let audioElement = $state(null);
  let searchQuery = $state('');
  let selectedLocale = $state('all');

  async function loadVoices() {
    log.tts.debug('loading_voices');
    const res = await fetch("/api/voices");
    voices = await res.json();
    log.tts.info('voices_loaded', { count: voices.length });
  }

  async function speak() {
    if (!text.trim()) return;
    loading = true;
    audioUrl = null;
    isPlaying = false;

    log.tts.info('synthesizing', { voice, textLength: text.length });

    try {
      const params = new URLSearchParams({ text, voice });
      const res = await fetch(`/api/tts?${params}`);
      const blob = await res.blob();
      audioUrl = URL.createObjectURL(blob);

      log.tts.info('synthesis_complete', { blobSize: blob.size });

      // Auto-play after load
      setTimeout(() => {
        if (audioElement) {
          audioElement.play();
          isPlaying = true;
        }
      }, 100);
    } catch (e) {
      log.tts.error('synthesis_failed', { error: e.message });
    } finally {
      loading = false;
    }
  }

  function handleAudioPlay() {
    isPlaying = true;
    log.audio.debug('playing');
  }

  function handleAudioPause() {
    isPlaying = false;
    log.audio.debug('paused');
  }

  function handleAudioEnded() {
    isPlaying = false;
    log.audio.debug('ended');
  }

  function getLocales() {
    const locales = [...new Set(voices.map(v => v.Locale))].sort();
    return locales;
  }

  function getFilteredVoices() {
    return voices.filter(v => {
      const matchesSearch = searchQuery === '' ||
        v.ShortName.toLowerCase().includes(searchQuery.toLowerCase()) ||
        v.Locale.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesLocale = selectedLocale === 'all' || v.Locale === selectedLocale;
      return matchesSearch && matchesLocale;
    });
  }

  function getVoiceInfo(shortName) {
    return voices.find(v => v.ShortName === shortName);
  }

  onMount(() => {
    loadVoices();
  });
</script>

<div class="tts-container">
  <!-- Header Section -->
  <div class="tts-header">
    <div class="header-title">
      <div class="title-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M11 5L6 9H2v6h4l5 4V5z"/>
          <path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
          <path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
        </svg>
      </div>
      <div class="title-text">
        <h2>VOICE SYNTHESIS</h2>
        <span class="subtitle">Neural text-to-speech engine</span>
      </div>
    </div>
    <div class="voice-count">
      <span class="count-number">{voices.length}</span>
      <span class="count-label">VOICES</span>
    </div>
  </div>

  <!-- Main Content Grid -->
  <div class="tts-grid">
    <!-- Voice Selection Panel -->
    <div class="voice-panel">
      <div class="panel-header">
        <span class="panel-label">SELECT VOICE</span>
        <div class="filter-row">
          <div class="search-box">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="11" cy="11" r="8"/>
              <path d="M21 21l-4.35-4.35"/>
            </svg>
            <input
              type="text"
              placeholder="Search voices..."
              bind:value={searchQuery}
            />
          </div>
          <select bind:value={selectedLocale} class="locale-filter">
            <option value="all">All Locales</option>
            {#each getLocales() as locale}
              <option value={locale}>{locale}</option>
            {/each}
          </select>
        </div>
      </div>

      <div class="voice-list">
        {#each getFilteredVoices() as v}
          <button
            class="voice-item"
            class:active={voice === v.ShortName}
            onclick={() => voice = v.ShortName}
          >
            <div class="voice-info">
              <span class="voice-name">{v.ShortName.split('-').slice(-1)[0].replace('Neural', '')}</span>
              <span class="voice-locale">{v.Locale}</span>
            </div>
            <div class="voice-gender" class:male={v.Gender === 'Male'} class:female={v.Gender === 'Female'}>
              {v.Gender === 'Male' ? 'M' : 'F'}
            </div>
          </button>
        {:else}
          <div class="no-voices">No voices found</div>
        {/each}
      </div>
    </div>

    <!-- Text Input & Controls Panel -->
    <div class="controls-panel">
      <!-- Selected Voice Display -->
      <div class="selected-voice">
        <span class="selected-label">ACTIVE VOICE</span>
        <div class="selected-info">
          {#if getVoiceInfo(voice)}
            <span class="selected-name">{voice}</span>
            <span class="selected-meta">{getVoiceInfo(voice)?.Locale} · {getVoiceInfo(voice)?.Gender}</span>
          {:else}
            <span class="selected-name">{voice}</span>
          {/if}
        </div>
      </div>

      <!-- Text Input -->
      <div class="text-section">
        <label class="input-label">
          <span class="label-text">INPUT TEXT</span>
          <span class="char-count">{text.length} chars</span>
        </label>
        <div class="textarea-wrapper">
          <textarea
            bind:value={text}
            rows="5"
            placeholder="Enter text to synthesize..."
          ></textarea>
          <div class="textarea-glow"></div>
        </div>
      </div>

      <!-- Action Button -->
      <button
        class="speak-btn"
        onclick={speak}
        disabled={loading || !text.trim()}
        class:loading
      >
        {#if loading}
          <div class="loading-spinner">
            <span></span>
            <span></span>
            <span></span>
          </div>
          <span>SYNTHESIZING</span>
        {:else}
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z"/>
          </svg>
          <span>SYNTHESIZE</span>
        {/if}
      </button>

      <!-- Audio Player -->
      {#if audioUrl}
        <div class="audio-section">
          <div class="audio-header">
            <span class="audio-label">OUTPUT</span>
            <span class="audio-status" class:playing={isPlaying}>
              {isPlaying ? 'PLAYING' : 'READY'}
            </span>
          </div>
          <div class="audio-player" class:playing={isPlaying}>
            <audio
              bind:this={audioElement}
              controls
              src={audioUrl}
              onplay={handleAudioPlay}
              onpause={handleAudioPause}
              onended={handleAudioEnded}
            ></audio>
            <div class="waveform">
              {#each Array(20) as _, i}
                <div
                  class="wave-bar"
                  class:active={isPlaying}
                  style="--i: {i}; --h: {20 + Math.random() * 60}%"
                ></div>
              {/each}
            </div>
          </div>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .tts-container {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: var(--space-lg);
    gap: var(--space-lg);
  }

  /* Header */
  .tts-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-bottom: var(--space-lg);
    border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  }

  .header-title {
    display: flex;
    align-items: center;
    gap: var(--space-md);
  }

  .title-icon {
    width: 40px;
    height: 40px;
    padding: var(--space-sm);
    background: linear-gradient(135deg, var(--pink-glow), var(--amber-glow));
    border-radius: var(--radius-md);
    color: var(--pink);
  }

  .title-icon svg {
    width: 100%;
    height: 100%;
  }

  .title-text h2 {
    font-family: var(--font-display);
    font-size: 1.1rem;
    letter-spacing: 0.2em;
    color: var(--text-primary);
    margin: 0;
  }

  .title-text .subtitle {
    font-size: 0.7rem;
    color: var(--text-muted);
    letter-spacing: 0.1em;
  }

  .voice-count {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    padding: var(--space-sm) var(--space-md);
    background: var(--carbon);
    border-radius: var(--radius-md);
    border: 1px solid rgba(255, 255, 255, 0.04);
  }

  .count-number {
    font-size: 1.5rem;
    font-weight: 700;
    color: var(--amber);
    line-height: 1;
  }

  .count-label {
    font-size: 0.55rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
  }

  /* Grid Layout */
  .tts-grid {
    display: grid;
    grid-template-columns: 280px 1fr;
    gap: var(--space-lg);
    flex: 1;
    min-height: 0;
  }

  /* Voice Panel */
  .voice-panel {
    display: flex;
    flex-direction: column;
    background: var(--carbon);
    border-radius: var(--radius-md);
    border: 1px solid rgba(255, 255, 255, 0.04);
    overflow: hidden;
  }

  .panel-header {
    padding: var(--space-md);
    border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  }

  .panel-label {
    display: block;
    font-size: 0.6rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
    margin-bottom: var(--space-sm);
  }

  .filter-row {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
  }

  .search-box {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    padding: var(--space-sm);
    background: var(--obsidian);
    border-radius: var(--radius-sm);
    border: 1px solid rgba(255, 255, 255, 0.04);
  }

  .search-box svg {
    width: 14px;
    height: 14px;
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .search-box input {
    flex: 1;
    background: transparent;
    border: none;
    color: var(--text-primary);
    font-size: 0.8rem;
    padding: 0;
  }

  .search-box input:focus {
    outline: none;
    box-shadow: none;
  }

  .locale-filter {
    padding: var(--space-sm);
    background: var(--obsidian);
    border: 1px solid rgba(255, 255, 255, 0.04);
    border-radius: var(--radius-sm);
    color: var(--text-secondary);
    font-size: 0.75rem;
  }

  .voice-list {
    flex: 1;
    overflow-y: auto;
    padding: var(--space-sm);
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .voice-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: var(--space-sm) var(--space-md);
    background: transparent;
    border-radius: var(--radius-sm);
    color: var(--text-secondary);
    font-size: 0.75rem;
    text-align: left;
    border: 1px solid transparent;
  }

  .voice-item:hover {
    background: var(--slate);
    color: var(--text-primary);
  }

  .voice-item.active {
    background: rgba(255, 183, 0, 0.1);
    border-color: var(--amber);
    color: var(--amber);
  }

  .voice-info {
    display: flex;
    flex-direction: column;
  }

  .voice-name {
    font-weight: 500;
  }

  .voice-locale {
    font-size: 0.6rem;
    color: var(--text-muted);
  }

  .voice-item.active .voice-locale {
    color: var(--amber-dim);
  }

  .voice-gender {
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    font-size: 0.6rem;
    font-weight: 600;
    background: var(--slate);
    color: var(--text-muted);
  }

  .voice-gender.male {
    background: rgba(0, 255, 245, 0.15);
    color: var(--cyan);
  }

  .voice-gender.female {
    background: rgba(255, 45, 106, 0.15);
    color: var(--pink);
  }

  .no-voices {
    padding: var(--space-lg);
    text-align: center;
    color: var(--text-muted);
    font-size: 0.8rem;
  }

  /* Controls Panel */
  .controls-panel {
    display: flex;
    flex-direction: column;
    gap: var(--space-lg);
  }

  .selected-voice {
    padding: var(--space-md) var(--space-lg);
    background: var(--carbon);
    border-radius: var(--radius-md);
    border: 1px solid rgba(255, 183, 0, 0.2);
  }

  .selected-label {
    font-size: 0.55rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
  }

  .selected-info {
    display: flex;
    flex-direction: column;
    margin-top: var(--space-xs);
  }

  .selected-name {
    font-size: 1rem;
    font-weight: 600;
    color: var(--amber);
  }

  .selected-meta {
    font-size: 0.7rem;
    color: var(--text-muted);
  }

  /* Text Section */
  .text-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
  }

  .input-label {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .label-text {
    font-size: 0.6rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
  }

  .char-count {
    font-size: 0.65rem;
    color: var(--text-muted);
    padding: 2px 8px;
    background: var(--slate);
    border-radius: var(--radius-sm);
  }

  .textarea-wrapper {
    position: relative;
  }

  .textarea-wrapper textarea {
    width: 100%;
    padding: var(--space-lg);
    background: var(--carbon);
    border: 1px solid rgba(255, 255, 255, 0.04);
    border-radius: var(--radius-md);
    color: var(--text-primary);
    font-size: 0.95rem;
    line-height: 1.6;
    resize: vertical;
    min-height: 120px;
    transition: all 0.25s var(--ease-out);
  }

  .textarea-wrapper textarea:focus {
    border-color: var(--pink);
    box-shadow: 0 0 0 3px var(--pink-glow), 0 0 30px var(--pink-glow);
  }

  .textarea-glow {
    position: absolute;
    inset: 0;
    border-radius: var(--radius-md);
    pointer-events: none;
    opacity: 0;
    background: radial-gradient(ellipse at center, var(--pink-glow), transparent 70%);
    transition: opacity 0.3s ease;
  }

  .textarea-wrapper:focus-within .textarea-glow {
    opacity: 0.5;
  }

  /* Speak Button */
  .speak-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-sm);
    padding: var(--space-lg) var(--space-xl);
    background: linear-gradient(135deg, var(--pink), var(--pink-dim));
    color: white;
    font-size: 0.85rem;
    font-weight: 600;
    letter-spacing: 0.2em;
    border-radius: var(--radius-md);
    box-shadow: 0 4px 20px var(--pink-glow);
    transition: all 0.25s var(--ease-out);
  }

  .speak-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 8px 30px var(--pink-glow);
  }

  .speak-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    transform: none;
  }

  .speak-btn svg {
    width: 20px;
    height: 20px;
  }

  .loading-spinner {
    display: flex;
    gap: 4px;
  }

  .loading-spinner span {
    width: 6px;
    height: 6px;
    background: white;
    border-radius: 50%;
    animation: loading-bounce 1s ease-in-out infinite;
  }

  .loading-spinner span:nth-child(2) {
    animation-delay: 0.1s;
  }

  .loading-spinner span:nth-child(3) {
    animation-delay: 0.2s;
  }

  @keyframes loading-bounce {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-8px); }
  }

  /* Audio Section */
  .audio-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
    animation: slide-up 0.4s var(--ease-out);
  }

  .audio-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .audio-label {
    font-size: 0.6rem;
    letter-spacing: 0.2em;
    color: var(--text-muted);
  }

  .audio-status {
    font-size: 0.6rem;
    letter-spacing: 0.15em;
    padding: 2px 8px;
    background: var(--slate);
    border-radius: var(--radius-sm);
    color: var(--text-muted);
  }

  .audio-status.playing {
    background: var(--green-glow);
    color: var(--green);
  }

  .audio-player {
    padding: var(--space-md);
    background: var(--carbon);
    border-radius: var(--radius-md);
    border: 1px solid rgba(255, 255, 255, 0.04);
    overflow: hidden;
  }

  .audio-player.playing {
    border-color: rgba(0, 255, 136, 0.2);
  }

  .audio-player audio {
    width: 100%;
    height: 36px;
    opacity: 0.8;
  }

  .audio-player audio::-webkit-media-controls-panel {
    background: var(--obsidian);
  }

  .waveform {
    display: flex;
    align-items: flex-end;
    justify-content: center;
    gap: 3px;
    height: 40px;
    margin-top: var(--space-md);
    padding-top: var(--space-sm);
    border-top: 1px solid rgba(255, 255, 255, 0.04);
  }

  .wave-bar {
    width: 4px;
    height: 20%;
    background: var(--steel);
    border-radius: 2px;
    transition: all 0.15s ease;
  }

  .wave-bar.active {
    height: var(--h);
    background: linear-gradient(0deg, var(--green), var(--cyan));
    animation: wave 0.5s ease-in-out infinite alternate;
    animation-delay: calc(var(--i) * 0.05s);
  }

  @keyframes wave {
    from { height: var(--h); }
    to { height: calc(var(--h) * 0.4); }
  }
</style>
