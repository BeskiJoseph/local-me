import admin, { db } from '../config/firebase.js';
import logger from '../utils/logger.js';

/**
 * Audit Logging Service
 * Records sensitive actions to a dedicated immutable collection.
 */
class AuditService {
    static async logAction({ userId, action, metadata = {}, req = null }) {
        try {
            const logEntry = {
                userId,
                action,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                metadata,
                ip: req?.ip || 'internal',
                userAgent: req?.headers['user-agent'] || 'unknown'
            };

            await db.collection('audit_logs').add(logEntry);

            // Also log to console/pino for real-time observability
            // Create a sanitized version for the logger to avoid serializing complex objects like FieldValue
            const { timestamp, ...logContent } = logEntry;
            logger.info({
                audit: true,
                ...logContent,
                timestamp: new Date().toISOString()
            }, `Audit Log: ${action}`);
        } catch (error) {
            // We don't want to crash the main request if audit logging fails, 
            // but we MUST log the failure.
            logger.error({ err: error, userId, action }, 'FAILED TO WRITE AUDIT LOG');
        }
    }
}

export default AuditService;
