const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const bodyParser = require('body-parser');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, 'public')));

// Database Setup - PostgreSQL
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.DATABASE_URL ? { rejectUnauthorized: false } : false
});

// Initialize tables
async function initDB() {
    try {
        await pool.query(`
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                device_id TEXT,
                start_time BIGINT,
                end_time BIGINT,
                is_active INTEGER
            )
        `);
        await pool.query(`
            CREATE TABLE IF NOT EXISTS locations (
                id SERIAL PRIMARY KEY,
                session_id TEXT REFERENCES sessions(id),
                latitude REAL,
                longitude REAL,
                timestamp BIGINT
            )
        `);
        console.log('Database tables initialized');
    } catch (err) {
        console.error('Error initializing database:', err.message);
    }
}

initDB();

// API Endpoints

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', timestamp: Date.now() });
});

// Start a session
app.post('/api/session/start', async (req, res) => {
    const { deviceId, duration } = req.body;
    const sessionId = `${deviceId}-${Date.now()}`;
    const startTime = Date.now();
    const endTime = startTime + (duration || 12 * 60 * 60 * 1000);

    try {
        await pool.query(
            `INSERT INTO sessions (id, device_id, start_time, end_time, is_active) VALUES ($1, $2, $3, $4, $5)`,
            [sessionId, deviceId, startTime, endTime, 1]
        );
        res.json({ sessionId, startTime, endTime });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Stop a session
app.post('/api/session/stop', async (req, res) => {
    const { sessionId } = req.body;
    try {
        await pool.query(`UPDATE sessions SET is_active = 0 WHERE id = $1`, [sessionId]);
        res.json({ message: 'Session stopped' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Report location (Single or Batch)
app.post('/api/location', async (req, res) => {
    const body = req.body;
    const locations = Array.isArray(body) ? body : [body];

    if (locations.length === 0) return res.json({ message: 'No data' });

    const sessionId = locations[0].sessionId;

    try {
        // Check session exists
        const sessionResult = await pool.query(`SELECT * FROM sessions WHERE id = $1`, [sessionId]);
        if (sessionResult.rows.length === 0) {
            return res.status(404).json({ error: 'Session not found' });
        }

        // Insert all locations
        for (const loc of locations) {
            await pool.query(
                `INSERT INTO locations (session_id, latitude, longitude, timestamp) VALUES ($1, $2, $3, $4)`,
                [sessionId, loc.latitude, loc.longitude, loc.timestamp || Date.now()]
            );
        }

        res.json({ message: `Recorded ${locations.length} locations` });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Get all sessions
app.get('/api/sessions', async (req, res) => {
    try {
        const result = await pool.query(`SELECT id, device_id as "deviceId", start_time as "startTime", end_time as "endTime", is_active as "isActive" FROM sessions ORDER BY start_time DESC`);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Get locations for a session
app.get('/api/session/:id/locations', async (req, res) => {
    const sessionId = req.params.id;
    try {
        const result = await pool.query(
            `SELECT id, session_id as "sessionId", latitude, longitude, timestamp FROM locations WHERE session_id = $1 ORDER BY timestamp ASC`,
            [sessionId]
        );
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
