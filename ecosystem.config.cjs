module.exports = {
  apps: [
    {
      name: 'redis',
      script: 'bash',
      args: '-c "docker rm -f bro-redis 2>/dev/null; docker run --rm --name bro-redis -p 6379:6379 redis:7 redis-server --bind 0.0.0.0"',
      autorestart: false,
    },
    {
      name: 'server',
      script: 'bash',
      args: '-c "sleep 1 && livekit-server --dev --redis-host localhost:6379"',
      autorestart: false,
    },
    {
      name: 'egress',
      script: 'bash',
      args: '-c "sleep 2 && just lk-egress"',
      autorestart: false,
      cwd: '/home/dima/projects/bro',
    },
    {
      name: 'agent',
      script: 'bash',
      args: '-c "uv run --project agent python agent/transcriber.py dev"',
      autorestart: true,
      watch: ['agent/*.py'],
      cwd: '/home/dima/projects/bro',
    },
  ],
};
