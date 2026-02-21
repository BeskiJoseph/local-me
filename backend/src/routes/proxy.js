import express from 'express';
import logger from '../utils/logger.js';

const router = express.Router();

// Whitelist of allowed proxy origins (prevents open-proxy abuse)
const ALLOWED_ORIGINS = [
    'media-proxy.beskijosphjr.workers.dev',
    'lh3.googleusercontent.com', // Google Profile Images
    'images.unsplash.com',       // Unsplash Demo Images
    process.env.R2_PUBLIC_BASE_URL?.replace('https://', '').split('/')[0],
].filter(Boolean);

/**
 * GET /api/proxy?url=<encoded_url>
 * Proxies media from Cloudflare R2 / Worker to bypass CORS on Flutter Web.
 */
router.get('/', async (req, res) => {
    const { url } = req.query;

    if (!url) {
        return res.status(400).json({ error: 'Missing url parameter' });
    }

    let parsedUrl;
    try {
        parsedUrl = new URL(decodeURIComponent(url));
    } catch {
        return res.status(400).json({ error: 'Invalid url parameter' });
    }

    // Security: only proxy from whitelisted origins
    const isAllowed = ALLOWED_ORIGINS.some((origin) => parsedUrl.hostname === origin);
    if (!isAllowed) {
        logger.warn({ hostname: parsedUrl.hostname }, 'Proxy blocked: origin not whitelisted');
        return res.status(403).json({ error: 'Proxy origin not allowed' });
    }

    try {
        const response = await fetch(parsedUrl.toString(), {
            headers: { 'User-Agent': 'LocalMe-Backend-Proxy/1.0' },
            signal: AbortSignal.timeout(15000), // 15s timeout for media fetch
        });

        if (!response.ok) {
            logger.warn({ url: parsedUrl.toString(), status: response.status }, 'Proxy upstream returned non-OK');
            return res.status(response.status).json({ error: 'Media not found upstream' });
        }

        const contentType = response.headers.get('content-type') || 'application/octet-stream';
        const contentLength = response.headers.get('content-length');

        res.set('Content-Type', contentType);
        res.set('Cache-Control', 'public, max-age=86400'); // Cache proxied media for 24h in browser
        if (contentLength) res.set('Content-Length', contentLength);

        // Stream the response body directly to client
        const buffer = await response.arrayBuffer();
        res.send(Buffer.from(buffer));

    } catch (err) {
        logger.error({ url: parsedUrl.toString(), error: err.message }, 'Proxy fetch failed');
        if (!res.headersSent) {
            res.status(502).json({ error: 'Failed to fetch media from upstream' });
        }
    }
});

export default router;
