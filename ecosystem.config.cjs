const fs = require("fs");
const path = require("path");

const apps = [
  {
    name: "meridian",
    script: "index.js",
    cwd: __dirname,
    interpreter: "node",
    instances: 1,
    exec_mode: "fork",
    autorestart: true,
    restart_delay: 5000,
    kill_timeout: 10000,
    max_restarts: 10,
    min_uptime: "10s",
    env: {
      NODE_ENV: "production",
    },
  },
];

// Optionally run the Discord listener (selfbot) under PM2 too — but ONLY when it is
// both configured (DISCORD_USER_TOKEN present in .env) AND installed
// (discord-listener/node_modules exists). This avoids a crash-looping process for
// users who don't use Discord. Configure it, run `npm run discord:install`, then
// `npm run pm2:start` again and it comes up automatically.
function discordConfigured() {
  try {
    const env = fs.readFileSync(path.join(__dirname, ".env"), "utf8");
    return /^\s*DISCORD_USER_TOKEN\s*=\s*\S+/m.test(env);
  } catch {
    return false;
  }
}

const discordDir = path.join(__dirname, "discord-listener");
if (discordConfigured() && fs.existsSync(path.join(discordDir, "node_modules"))) {
  apps.push({
    name: "discord-listener",
    script: "index.js",
    cwd: discordDir,
    interpreter: "node",
    instances: 1,
    exec_mode: "fork",
    autorestart: true,
    restart_delay: 5000,
    max_restarts: 10,
    min_uptime: "10s",
    env: {
      NODE_ENV: "production",
    },
  });
}

module.exports = { apps };
