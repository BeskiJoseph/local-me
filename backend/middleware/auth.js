import admin from 'firebase-admin';
import { logSecurityEvent } from '../utils/logger.js';

// Verify Firebase authentication token
export async function verifyFirebaseToken(req, res, next) {
    try {
        const auth = req.headers.authorization;

        if (!auth?.startsWith('Bearer ')) {
            logSecurityEvent('MISSING_AUTH_TOKEN', {
                ip: req.ip,
                path: req.path,
            });
            return res.status(401).json({ error: 'Unauthorized - No token provided' });
        }

        const token = auth.split('Bearer ')[1];

        if (!token) {
            logSecurityEvent('INVALID_AUTH_FORMAT', {
                ip: req.ip,
                path: req.path,
            });
            return res.status(401).json({ error: 'Unauthorized - Invalid token format' });
        }

        // Verify token with Firebase Admin SDK
        const decoded = await admin.auth().verifyIdToken(token, true); // checkRevoked = true

        // Attach user info to request
        req.user = {
            uid: decoded.uid,
            email: decoded.email,
            email_verified: decoded.email_verified,
            auth_time: decoded.auth_time,
            iat: decoded.iat,
            exp: decoded.exp,
        };

        next();
    } catch (error) {
        // Log specific error types
        if (error.code === 'auth/id-token-expired') {
            logSecurityEvent('EXPIRED_TOKEN', {
                ip: req.ip,
                path: req.path,
            });
            return res.status(401).json({ error: 'Token expired - Please re-authenticate' });
        }

        if (error.code === 'auth/id-token-revoked') {
            logSecurityEvent('REVOKED_TOKEN_USED', {
                ip: req.ip,
                path: req.path,
            });
            return res.status(401).json({ error: 'Token revoked - Please re-authenticate' });
        }

        logSecurityEvent('AUTH_VERIFICATION_FAILED', {
            ip: req.ip,
            path: req.path,
            error: error.message,
        });

        res.status(401).json({ error: 'Invalid or expired token' });
    }
}
