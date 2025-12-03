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
                accuracy REAL,
                speed REAL,
                timestamp BIGINT
            )
        `);
        // Add columns if they don't exist (for existing databases)
        await pool.query(`ALTER TABLE locations ADD COLUMN IF NOT EXISTS accuracy REAL`);
        await pool.query(`ALTER TABLE locations ADD COLUMN IF NOT EXISTS speed REAL`);
        
        await pool.query(`
            CREATE TABLE IF NOT EXISTS alerts (
                id SERIAL PRIMARY KEY,
                session_id TEXT REFERENCES sessions(id),
                type TEXT,
                message TEXT,
                latitude REAL,
                longitude REAL,
                timestamp BIGINT,
                is_read INTEGER DEFAULT 0
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
    console.log('📍 Received location request:', JSON.stringify(body));
    
    const locations = Array.isArray(body) ? body : [body];

    if (locations.length === 0) {
        console.log('📍 No locations in request');
        return res.json({ message: 'No data' });
    }

    const sessionId = locations[0].sessionId;
    console.log(`📍 Processing ${locations.length} locations for session: ${sessionId}`);

    try {
        // Check session exists
        const sessionResult = await pool.query(`SELECT * FROM sessions WHERE id = $1`, [sessionId]);
        if (sessionResult.rows.length === 0) {
            console.log(`📍 Session not found: ${sessionId}`);
            return res.status(404).json({ error: 'Session not found' });
        }

        // Insert all locations
        let insertedCount = 0;
        for (const loc of locations) {
            await pool.query(
                `INSERT INTO locations (session_id, latitude, longitude, accuracy, speed, timestamp) VALUES ($1, $2, $3, $4, $5, $6)`,
                [sessionId, loc.latitude, loc.longitude, loc.accuracy || null, loc.speed || null, loc.timestamp || Date.now()]
            );
            insertedCount++;
        }

        console.log(`📍 Successfully inserted ${insertedCount} locations`);
        res.json({ message: `Recorded ${locations.length} locations` });
    } catch (err) {
        console.error(`📍 Error inserting locations: ${err.message}`);
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
            `SELECT id, session_id as "sessionId", latitude, longitude, accuracy, speed, timestamp FROM locations WHERE session_id = $1 ORDER BY timestamp ASC`,
            [sessionId]
        );
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ========== ALERTS API ==========

// Device IDs to ignore for geofence alerts (trusted devices)
const IGNORED_GEOFENCE_DEVICE_IDS = [
    'AP3A.240905.015.A2',
    'UKQ1.230924.001',
];

// Report an alert
app.post('/api/alert', async (req, res) => {
    const { sessionId, type, message, latitude, longitude, timestamp } = req.body;

    try {
        // Extract device ID from session ID (format: deviceId-timestamp)
        const deviceId = sessionId.includes('-') 
            ? sessionId.substring(0, sessionId.lastIndexOf('-')) 
            : sessionId;
        
        // Skip geofence alerts for ignored devices
        if (type === 'GEOFENCE_ENTERED' && IGNORED_GEOFENCE_DEVICE_IDS.includes(deviceId)) {
            console.log(`🔕 Ignoring geofence alert for trusted device: ${deviceId}`);
            return res.json({ message: 'Alert ignored (trusted device)' });
        }

        await pool.query(
            `INSERT INTO alerts (session_id, type, message, latitude, longitude, timestamp) VALUES ($1, $2, $3, $4, $5, $6)`,
            [sessionId, type, message, latitude || null, longitude || null, timestamp || Date.now()]
        );
        console.log(`🚨 ALERT: ${type} - ${message}`);
        res.json({ message: 'Alert recorded' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Get all alerts (unread first)
app.get('/api/alerts', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT a.id, a.session_id as "sessionId", a.type, a.message, a.latitude, a.longitude, a.timestamp, a.is_read as "isRead", s.device_id as "deviceId"
            FROM alerts a
            LEFT JOIN sessions s ON a.session_id = s.id
            ORDER BY a.is_read ASC, a.timestamp DESC
            LIMIT 100
        `);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Get unread alert count
app.get('/api/alerts/unread/count', async (req, res) => {
    try {
        const result = await pool.query(`SELECT COUNT(*) as count FROM alerts WHERE is_read = 0`);
        res.json({ count: parseInt(result.rows[0].count) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Mark alert as read
app.post('/api/alert/:id/read', async (req, res) => {
    const alertId = req.params.id;
    try {
        await pool.query(`UPDATE alerts SET is_read = 1 WHERE id = $1`, [alertId]);
        res.json({ message: 'Alert marked as read' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Mark all alerts as read
app.post('/api/alerts/read-all', async (req, res) => {
    try {
        await pool.query(`UPDATE alerts SET is_read = 1`);
        res.json({ message: 'All alerts marked as read' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ========== EXPORT & STATISTICS API ==========

// Helper function to calculate distance between two points (Haversine)
function calculateDistanceKm(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth's radius in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
}

// Get session statistics
app.get('/api/session/:id/stats', async (req, res) => {
    const sessionId = req.params.id;
    try {
        // Get session info
        const sessionResult = await pool.query(
            `SELECT * FROM sessions WHERE id = $1`,
            [sessionId]
        );
        
        if (sessionResult.rows.length === 0) {
            return res.status(404).json({ error: 'Session not found' });
        }
        
        const session = sessionResult.rows[0];
        
        // Get locations
        const locResult = await pool.query(
            `SELECT latitude, longitude, speed, accuracy, timestamp FROM locations WHERE session_id = $1 ORDER BY timestamp ASC`,
            [sessionId]
        );
        
        const locations = locResult.rows;
        
        // Calculate statistics
        let totalDistanceKm = 0;
        let maxSpeed = 0;
        let totalSpeed = 0;
        let speedCount = 0;
        let minAccuracy = Infinity;
        let maxAccuracy = 0;
        
        for (let i = 0; i < locations.length; i++) {
            const loc = locations[i];
            
            // Distance from previous point
            if (i > 0) {
                const prev = locations[i - 1];
                totalDistanceKm += calculateDistanceKm(
                    prev.latitude, prev.longitude,
                    loc.latitude, loc.longitude
                );
            }
            
            // Speed stats (convert m/s to km/h)
            if (loc.speed !== null && loc.speed >= 0) {
                const speedKmh = loc.speed * 3.6;
                totalSpeed += speedKmh;
                speedCount++;
                if (speedKmh > maxSpeed) maxSpeed = speedKmh;
            }
            
            // Accuracy stats
            if (loc.accuracy !== null) {
                if (loc.accuracy < minAccuracy) minAccuracy = loc.accuracy;
                if (loc.accuracy > maxAccuracy) maxAccuracy = loc.accuracy;
            }
        }
        
        const startTime = parseInt(session.start_time);
        const endTime = session.is_active ? Date.now() : parseInt(session.end_time);
        const durationMs = endTime - startTime;
        const durationHours = durationMs / (1000 * 60 * 60);
        
        res.json({
            sessionId,
            deviceId: session.device_id,
            startTime,
            endTime: session.is_active ? null : parseInt(session.end_time),
            isActive: session.is_active === 1,
            locationCount: locations.length,
            totalDistanceKm: Math.round(totalDistanceKm * 100) / 100,
            durationHours: Math.round(durationHours * 100) / 100,
            avgSpeedKmh: speedCount > 0 ? Math.round((totalSpeed / speedCount) * 10) / 10 : 0,
            maxSpeedKmh: Math.round(maxSpeed * 10) / 10,
            avgAccuracyM: minAccuracy !== Infinity ? Math.round((minAccuracy + maxAccuracy) / 2) : null,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Export session as CSV
app.get('/api/session/:id/export/csv', async (req, res) => {
    const sessionId = req.params.id;
    try {
        const result = await pool.query(
            `SELECT latitude, longitude, accuracy, speed, timestamp FROM locations WHERE session_id = $1 ORDER BY timestamp ASC`,
            [sessionId]
        );
        
        // Build CSV
        let csv = 'timestamp,datetime,latitude,longitude,accuracy_m,speed_ms,speed_kmh\n';
        for (const loc of result.rows) {
            const timestamp = parseInt(loc.timestamp);
            const datetime = new Date(timestamp).toISOString();
            const speedKmh = loc.speed ? (loc.speed * 3.6).toFixed(2) : '';
            csv += `${timestamp},${datetime},${loc.latitude},${loc.longitude},${loc.accuracy || ''},${loc.speed || ''},${speedKmh}\n`;
        }
        
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', `attachment; filename="locus-${sessionId}.csv"`);
        res.send(csv);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Export session as GPX
app.get('/api/session/:id/export/gpx', async (req, res) => {
    const sessionId = req.params.id;
    try {
        const sessionResult = await pool.query(`SELECT * FROM sessions WHERE id = $1`, [sessionId]);
        const locResult = await pool.query(
            `SELECT latitude, longitude, accuracy, speed, timestamp FROM locations WHERE session_id = $1 ORDER BY timestamp ASC`,
            [sessionId]
        );
        
        const session = sessionResult.rows[0];
        const startTime = new Date(parseInt(session.start_time)).toISOString();
        
        // Build GPX
        let gpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Locus Tracker"
    xmlns="http://www.topografix.com/GPX/1/1"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>Locus Track - ${sessionId}</name>
    <time>${startTime}</time>
  </metadata>
  <trk>
    <name>Session ${sessionId}</name>
    <trkseg>
`;
        
        for (const loc of locResult.rows) {
            const timestamp = parseInt(loc.timestamp);
            const time = new Date(timestamp).toISOString();
            gpx += `      <trkpt lat="${loc.latitude}" lon="${loc.longitude}">
        <time>${time}</time>
${loc.speed !== null ? `        <extensions><speed>${loc.speed}</speed></extensions>\n` : ''}      </trkpt>
`;
        }
        
        gpx += `    </trkseg>
  </trk>
</gpx>`;
        
        res.setHeader('Content-Type', 'application/gpx+xml');
        res.setHeader('Content-Disposition', `attachment; filename="locus-${sessionId}.gpx"`);
        res.send(gpx);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
