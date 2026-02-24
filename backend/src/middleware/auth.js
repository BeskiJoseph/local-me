import { auth, db } from '../config/firebase.js';
import logger from '../utils/logger.js';
import jwt from 'jsonwebtoken';

// In-memory cache for user profiles to reduce Firestore overhead (30s TTL)
const USER_CACHE = new Map();
const CACHE_TTL = 30 * 1000;

export const clearUserCache = (uid) => {
    USER_CACHE.delete(`profile_${uid}`);
};

/**
 * Enterprise Auth Middleware
 * - Verifies Firebase ID Token
 * - Checks for token revocation (checkRevoked: true)
 * - Attaches user object with role and existence check
 */
const authenticate = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader?.startsWith('Bearer ')) {
            const error = new Error('No authentication token provided');
            error.status = 401;
            error.code = 'auth/no-token';
            return next(error);
        }

        const token = authHeader.split('Bearer ')[1];

        // 1. Try Custom JWT First (Short-lived Access Token)
        if (process.env.JWT_ACCESS_SECRET) {
            try {
                const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET);

                // Fetch user from cache or DB (Optimized)
                const cacheKey = `profile_${decoded.uid}`;
                const cached = USER_CACHE.get(cacheKey);
                let userData;

                if (cached && (Date.now() - cached.timestamp < CACHE_TTL)) {
                    userData = cached.data;
                } else {
                    const userDoc = await db.collection('users').doc(decoded.uid).get();
                    userData = userDoc.exists ? userDoc.data() : null;
                    USER_CACHE.set(cacheKey, { data: userData, timestamp: Date.now() });
                }

                req.user = {
                    uid: decoded.uid,
                    email: decoded.email,
                    displayName: userData?.displayName || userData?.username || 'User',
                    photoURL: userData?.profileImageUrl || userData?.photoURL,
                    role: userData?.role || 'user',
                    status: userData?.status || 'active',
                    auth_type: 'custom',
                    tokenVersion: userData?.tokenVersion || 1
                };

                // Security Mature: Version Check (Instant Kill Switch)
                if (decoded.version !== req.user.tokenVersion) {
                    logger.warn({ uid: decoded.uid, token: decoded.version, current: req.user.tokenVersion }, 'Security Version Mismatch - Forcing Logout');
                    throw { code: 'auth/session-expired', message: 'Session expired by security policy' };
                }

                if (req.user.status === 'suspended') {
                    throw { code: 'auth/account-suspended', message: 'Account suspended' };
                }

                return next();
            } catch (jwtError) {
                // If it's a JWT error but NOT expired, it might be a Firebase token
                if (jwtError.name === 'TokenExpiredError') {
                    const error = new Error('Authentication token has expired');
                    error.status = 401;
                    error.code = 'auth/token-expired';
                    return next(error);
                }
                // Continue to Firebase check if not a valid custom JWT
            }
        }

        // 2. Fallback to Firebase ID Token
        try {
            // Re-enabled revocation check (Architectural Fix)
            // Note: Requires "Service Account Token Creator" IAM role
            const decodedToken = await auth.verifyIdToken(token, true);

            // Fetch user from cache or DB (Standard fallback)
            const cacheKey = `profile_${decodedToken.uid}`;
            const cached = USER_CACHE.get(cacheKey);
            let userData;
            let profileExists = false;

            if (cached && (Date.now() - cached.timestamp < CACHE_TTL)) {
                userData = cached.data;
                profileExists = !!userData; // If we have data in cache, profile exists
            } else {
                const userDoc = await db.collection('users').doc(decodedToken.uid).get();
                userData = userDoc.exists ? userDoc.data() : null;
                profileExists = userDoc.exists;
                USER_CACHE.set(cacheKey, { data: userData, timestamp: Date.now() });
            }

            // Attach sanitized user info to request
            req.user = {
                uid: decodedToken.uid,
                email: decodedToken.email,
                auth_time: decodedToken.auth_time,
                profileExists: profileExists,
                displayName: userData?.displayName || userData?.username || decodedToken.name || 'User',
                photoURL: userData?.profileImageUrl || userData?.photoURL || decodedToken.picture,
                role: userData?.role || 'user',
                status: userData?.status || 'active',
                auth_type: 'firebase'
            };

            // Check if user is banned/suspended
            if (req.user.status === 'suspended') {
                const error = new Error('Account has been suspended');
                error.status = 403;
                error.code = 'auth/account-suspended';
                return next(error);
            }

            next();
        } catch (verifyError) {
            const error = new Error(verifyError.message);
            error.status = 401;

            if (verifyError.code === 'auth/id-token-expired') {
                error.code = 'auth/token-expired';
                error.message = 'Authentication token has expired';
            } else if (verifyError.code === 'auth/id-token-revoked') {
                error.code = 'auth/token-revoked';
                error.message = 'Authentication token has been revoked';
            } else {
                error.code = 'auth/invalid-token';
            }

            next(error);
        }
    } catch (err) {
        next(err);
    }
};

export default authenticate;
