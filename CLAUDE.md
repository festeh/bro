# bro Development Guidelines

## Logs

Services are managed by pm2. Logs are stored in `/tmp/bro-logs/`:

- `agent.log` - Voice/text agent (livekit-agents)
- `server.log` - LiveKit server
- `app.log` - Flutter app
- `redis.log` - Redis
- `egress.log` - LiveKit egress

View logs:
```bash
pm2 logs agent --lines 100
tail -f /tmp/bro-logs/agent.log
```

<!-- MANUAL ADDITIONS END -->
