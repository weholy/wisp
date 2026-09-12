import { createServer } from 'node:http';
import express from 'express';
import { authRouter } from './auth/routes.js';
import { chatRouter } from './chat/routes.js';
import { config } from './config.js';
import { applyAdminBootstrap, startBotPolling } from './telegramBot.js';
import { attachWebSocket } from './ws/server.js';

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => res.json({ ok: true }));
app.use('/auth', authRouter);
app.use('/chats', chatRouter);

const server = createServer(app);
attachWebSocket(server);

server.listen(config.port, () => {
    console.log(`netegram-native server listening on :${config.port}`);
});

applyAdminBootstrap();
startBotPolling();
