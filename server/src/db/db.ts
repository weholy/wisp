import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../config.js';

/**
 * SQLite via Node's built-in driver: zero setup for local development and for
 * a single-server deployment, which is exactly where this project is right
 * now. The data-access calls elsewhere use plain parameterized SQL rather
 * than an ORM, so moving to Postgres later (once there is more than one
 * server process, or write volume that needs it) means swapping this one
 * file and the two or three places using SQLite-specific syntax — not
 * rewriting every query.
 */
mkdirSync(dirname(config.dbPath), { recursive: true });

export const db = new DatabaseSync(config.dbPath);
db.exec('PRAGMA journal_mode = WAL;');
db.exec('PRAGMA foreign_keys = ON;');

const schemaPath = fileURLToPath(new URL('./schema.sql', import.meta.url));
db.exec(readFileSync(schemaPath, 'utf8'));
