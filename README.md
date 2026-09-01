# discourse-discord-bot

A Discord bot that runs on your Discourse server to link the two servers.

Enable the **Server Members Intent** and **Message Content Intent** for the bot in the Discord
developer portal. The bot needs these privileged gateway intents to synchronize roles, process
commands, and copy message content.

[Read more about this project, a Discourse plugin, here](https://meta.discourse.org/t/discord-bot-run-one-on-your-discourse-server-keep-things-in-sync/122530)

## Logging

Supervisor process creation, shutdown, and unexpected lease loss are logged at `WARN`. Enable the
`discord_bot_verbose_logging` site setting to also log lease and per-site gateway lifecycle details
at `WARN`, which makes them available in production logs. Reconciliation polling is not logged.
