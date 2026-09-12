-- One user per phone number. telegram_chat_id is the chat with our bot that
-- delivers login codes; it is set the moment someone shares their contact with
-- the bot and is required before a login code can be sent to that phone.
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL UNIQUE,
    telegram_chat_id INTEGER,
    display_name TEXT NOT NULL,
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
