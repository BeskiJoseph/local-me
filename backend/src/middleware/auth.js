import { auth, db } from '../config/firebase.js';
import logger from '../utils/logger.js';

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

        try {
            // Enterprise Upgrade: enable revocation check
            const decodedToken = await auth.verifyIdToken(token, true);

            // Fetch user from DB to verify existence and attach role
            const userDoc = await db.collection('users').doc(decodedToken.uid).get();
            const userData = userDoc.exists ? userDoc.data() : null;

            // Attach sanitized user info to request
            req.user = {
                uid: decodedToken.uid,
                email: decodedToken.email,
                auth_time: decodedToken.auth_time,
                profileExists: userDoc.exists,
                displayName: userData?.username || userData?.displayName || decodedToken.name || 'User',
                photoURL: userData?.profileImageUrl || userData?.photoURL || decodedToken.picture,
                role: userData?.role || 'user',
                status: userData?.status || 'active'
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

            // Explicit handling for expired tokens (CTO suggestion)
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
