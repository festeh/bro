const logDir = '/tmp/bro-logs';
const projectDir = __dirname;

module.exports = {
  apps: [
    {
      name: 'redis',
      script: './scripts/redis.sh',
      autorestart: false,
      cwd: projectDir,
      out_file: `${logDir}/redis.log`,
      error_file: `${logDir}/redis.log`,
    },
    {
      name: 'server',
      script: './scripts/server.sh',
      autorestart: false,
      cwd: projectDir,
      out_file: `${logDir}/server.log`,
      error_file: `${logDir}/server.log`,
    },
    {
      name: 'egress',
      script: './scripts/egress.sh',
      autorestart: false,
      cwd: projectDir,
      out_file: `${logDir}/egress.log`,
      error_file: `${logDir}/egress.log`,
    },
    {
      name: 'agent',
      script: './scripts/agent.sh',
      autorestart: true,
      cwd: projectDir,
      out_file: `${logDir}/agent.log`,
      error_file: `${logDir}/agent.log`,
    },
    {
      name: 'app',
      script: './scripts/app.sh',
      autorestart: false,
      cwd: projectDir,
      out_file: `${logDir}/app.log`,
      error_file: `${logDir}/app.log`,
    },
  ],
};
