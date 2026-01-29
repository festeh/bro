const logDir = '/tmp/bro-logs';
const projectDir = __dirname;

module.exports = {
  apps: [
    {
      name: 'redis',
      script: 'bash',
      args: '-c "docker rm -f bro-redis 2>/dev/null; docker run --rm --name bro-redis -p 6379:6379 redis:7 redis-server --bind 0.0.0.0"',
      autorestart: false,
      out_file: `${logDir}/redis.log`,
      error_file: `${logDir}/redis.log`,
    },
    {
      name: 'server',
      script: 'bash',
      args: '-c "sleep 1 && livekit-server --dev --redis-host localhost:6379"',
      autorestart: false,
      out_file: `${logDir}/server.log`,
      error_file: `${logDir}/server.log`,
    },
    {
      name: 'egress',
      script: 'bash',
      args: '-c "sleep 2 && just lk-egress"',
      autorestart: false,
      cwd: projectDir,
      out_file: `${logDir}/egress.log`,
      error_file: `${logDir}/egress.log`,
    },
    {
      name: 'agent',
      script: 'bash',
      args: '-c "set -a && source .env && set +a && PYTHONPATH=$PWD uv run python agent/voice_agent.py dev"',
      autorestart: true,
      cwd: projectDir,
      out_file: `${logDir}/agent.log`,
      error_file: `${logDir}/agent.log`,
    },
    {
      name: 'app',
      script: 'bash',
      args: '-c "until curl -s http://localhost:8081 >/dev/null 2>&1; do sleep 0.5; done && just sync-models && cd app && flutter run -d linux"',
      autorestart: false,
      cwd: projectDir,
      out_file: `${logDir}/app.log`,
      error_file: `${logDir}/app.log`,
    },
  ],
};
