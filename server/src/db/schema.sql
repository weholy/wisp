-- wisp_number is a display identifier shaped like a phone number — it is not
-- a real, dialable telecom number and nothing is ever sent to it outside
-- this bot. It exists so someone can have a Wisp account without exposing
-- their real phone number: free accounts get a random one, Stars unlock
-- picking a specific look or typing a custom string (see telegramBot.ts).
--
-- telegram_chat_id is what makes the account real: it is the actual chat
-- with our bot, on the person's own Telegram account, and it is the only
-- place a login code for THIS account is ever delivered — regardless of
-- which wisp_number is attached to it.
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wisp_number TEXT NOT NULL UNIQUE,
    telegram_chat_id INTEGER NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    is_premium INTEGER NOT NULL DEFAULT 0,
    -- Set only via the ADMIN_CHAT_IDS env var at startup (see config.ts /
    -- applyAdminBootstrap), never by anything reachable through the bot
    -- itself — there is no button or command that grants this.
    is_admin INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);

-- One row per Stars payment the bot has actually seen, keyed by Telegram's
-- own charge id so a redelivered update (Telegram retries if we're slow to
-- answer) cannot be counted twice.
CREATE TABLE IF NOT EXISTS payments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_chat_id INTEGER NOT NULL,
    charge_id TEXT NOT NULL UNIQUE,
    stars INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);

-- A session is a bare bearer token. No expiry column yet — sign-out-everywhere
-- and token rotation are not implemented, matching the size of everything else
-- in this v1.
CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    created_at INTEGER NOT NULL
);

-- 'direct' chats always have exactly two chat_members rows and no title; the
-- shape already fits groups (kind = 'group', a title, more members) so that
-- feature is additive later rather than a schema migration.
CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL CHECK (kind IN ('direct', 'group')),
    title TEXT,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_members (
    chat_id INTEGER NOT NULL REFERENCES chats(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL REFERENCES chats(id),
    sender_id INTEGER NOT NULL REFERENCES users(id),
    text TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_chat ON messages(chat_id, id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user ON chat_members(user_id);
