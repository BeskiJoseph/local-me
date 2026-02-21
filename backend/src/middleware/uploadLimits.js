import admin from 'firebase-admin';
import logger from '../utils/logger.js';

const db = admin.firestore();

/**
 * Middleware to check daily upload limit for a user
 * Limit: 20 uploads per user per day
 */
export const checkDailyUploadLimit = async (req, res, next) => {
    try {
        const userId = req.user.uid;
        const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
        const limitDocRef = db.collection('daily_uploads').doc(`${userId}_${today}`);

        const doc = await limitDocRef.get();
        const count = doc.exists ? doc.data().count : 0;

        if (count >= 20) {
            logger.warn('Daily upload limit reached', { userId, today, count });
            return res.status(429).json({
                error: 'Daily upload limit reached (20 videos per day)',
                retryAfter: 'tomorrow'
            });
        }

        // Pass count to request object if needed
        req.dailyUploadCount = count;
        next();
    } catch (err) {
        logger.error('Error checking daily upload limit', { error: err.message, userId: req.user.uid });
        // Fail-safe: allow upload if check fails? Or block?
        // Let's allow but log error for now, or block to be strict.
        next();
    }
};

/**
 * Increment daily upload count for a user
 * Should be called AFTER successful upload to R2
 */
export const incrementDailyUploadCount = async (userId) => {
    const today = new Date().toISOString().split('T')[0];
    const limitDocRef = db.collection('daily_uploads').doc(`${userId}_${today}`);

    try {
        await limitDocRef.set({
            count: admin.firestore.FieldValue.increment(1),
            lastUpload: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
    } catch (err) {
        logger.error('Error incrementing daily upload count', { error: err.message, userId, today });
    }
};
