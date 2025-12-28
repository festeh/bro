/**
 * Terminal Noir Logger - Styled console logging for the debug console.
 *
 * Usage:
 *   import { log } from './logger.js';
 *   log.info('message', { key: 'value' });
 *   log.ws('connected', { threadId: '123' });
 */

const LEVELS = {
  debug: { priority: 0, color: '#8888a0', badge: 'DBG' },
  info: { priority: 1, color: '#00fff5', badge: 'INF' },
  warn: { priority: 2, color: '#ffb700', badge: 'WRN' },
  error: { priority: 3, color: '#ff3366', badge: 'ERR' },
};

const SCOPES = {
  app: { color: '#00fff5', label: 'APP' },
  ws: { color: '#00ff88', label: 'WS' },
  chat: { color: '#ff2d6a', label: 'CHAT' },
  tts: { color: '#ffb700', label: 'TTS' },
  audio: { color: '#cc9200', label: 'AUDIO' },
};

// Configuration
let config = {
  minLevel: 'debug',
  enabled: true,
  showTimestamp: true,
  showScope: true,
};

/**
 * Format timestamp in HH:MM:SS.mmm format
 */
function formatTime() {
  const now = new Date();
  const h = String(now.getHours()).padStart(2, '0');
  const m = String(now.getMinutes()).padStart(2, '0');
  const s = String(now.getSeconds()).padStart(2, '0');
  const ms = String(now.getMilliseconds()).padStart(3, '0');
  return `${h}:${m}:${s}.${ms}`;
}

/**
 * Create styled console arguments
 */
function createLogArgs(level, scope, message, data) {
  const levelConfig = LEVELS[level];
  const scopeConfig = SCOPES[scope] || SCOPES.app;

  const parts = [];
  const styles = [];

  // Timestamp
  if (config.showTimestamp) {
    parts.push(`%c${formatTime()}`);
    styles.push('color: #555566; font-size: 10px;');
  }

  // Level badge
  parts.push(`%c ${levelConfig.badge} `);
  styles.push(
    `background: ${levelConfig.color}22; color: ${levelConfig.color}; ` +
    'padding: 1px 4px; border-radius: 2px; font-weight: 600; font-size: 10px;'
  );

  // Scope badge
  if (config.showScope) {
    parts.push(`%c ${scopeConfig.label} `);
    styles.push(
      `background: ${scopeConfig.color}22; color: ${scopeConfig.color}; ` +
      'padding: 1px 4px; border-radius: 2px; font-size: 10px;'
    );
  }

  // Message
  parts.push(`%c${message}`);
  styles.push(`color: #e8e8f0; font-weight: 500;`);

  // Data (if any)
  if (data && Object.keys(data).length > 0) {
    parts.push('%c' + JSON.stringify(data));
    styles.push('color: #8888a0; font-size: 11px;');
  }

  return [parts.join(' '), ...styles];
}

/**
 * Log a message at the specified level
 */
function logMessage(level, scope, message, data = {}) {
  if (!config.enabled) return;

  const levelConfig = LEVELS[level];
  const minLevelConfig = LEVELS[config.minLevel];

  if (levelConfig.priority < minLevelConfig.priority) return;

  const args = createLogArgs(level, scope, message, data);

  switch (level) {
    case 'error':
      console.error(...args);
      break;
    case 'warn':
      console.warn(...args);
      break;
    default:
      console.log(...args);
  }
}

/**
 * Create a scoped logger
 */
function createScopedLogger(scope) {
  return {
    debug: (msg, data) => logMessage('debug', scope, msg, data),
    info: (msg, data) => logMessage('info', scope, msg, data),
    warn: (msg, data) => logMessage('warn', scope, msg, data),
    error: (msg, data) => logMessage('error', scope, msg, data),
  };
}

/**
 * Main logger with scoped sub-loggers
 */
export const log = {
  // Generic logging methods (app scope)
  debug: (msg, data) => logMessage('debug', 'app', msg, data),
  info: (msg, data) => logMessage('info', 'app', msg, data),
  warn: (msg, data) => logMessage('warn', 'app', msg, data),
  error: (msg, data) => logMessage('error', 'app', msg, data),

  // Scoped loggers
  ws: createScopedLogger('ws'),
  chat: createScopedLogger('chat'),
  tts: createScopedLogger('tts'),
  audio: createScopedLogger('audio'),

  // Configuration
  configure: (options) => {
    config = { ...config, ...options };
  },

  // Create custom scoped logger
  scope: (scopeName, scopeColor = '#8888a0') => {
    SCOPES[scopeName] = { color: scopeColor, label: scopeName.toUpperCase().slice(0, 5) };
    return createScopedLogger(scopeName);
  },
};

// Log initialization
log.debug('logger_initialized', { scopes: Object.keys(SCOPES) });

export default log;
