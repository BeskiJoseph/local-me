import crypto from 'crypto';

/**
 * Extracts and hashes device/client fingerprints to ensure raw identifying data
 * (like IPs or long UAs) stays out of the database for both security and privacy.
 */
export function deviceContext(req, res, next) {
    const ip = req.headers['x-forwarded-for']?.split(',')[0] || req.ip || req.socket?.remoteAddress || 'unknown';
    const ua = req.headers['user-agent'] || 'unknown';
    const deviceId = req.headers['x-device-id'];

    if (req.path === '/refresh' && !deviceId) {
        return res.status(400).json({ success: false, error: 'device_id_required' });
    }

    req.deviceContext = {
        ipHash: crypto.createHash('sha256').update(ip).digest('hex'),
        userAgentHash: crypto.createHash('sha256').update(ua).digest('hex'),
        deviceIdHash: crypto.createHash('sha256').update(deviceId || 'unknown').digest('hex')
    };

    next();
}
