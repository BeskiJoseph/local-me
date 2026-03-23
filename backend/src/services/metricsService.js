import { db } from '../config/firebase.js';
import admin from 'firebase-admin';
import logger from '../utils/logger.js';

/**
 * Super-lightweight Metrics Service
 * Tracks daily aggregate counters in Firestore for system health/growth monitoring.
 */
class MetricsService {
    /**
     * Increment a metric counter for today
     * @param {string} metricName - 'searches', 'messages', 'notifications_sent'
     */
    static async track(metricName) {
        try {
            const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
            const metricsRef = db.collection('system_metrics').doc(today);

            // Simple atomic increment
            await metricsRef.set({
                [metricName]: admin.firestore.FieldValue.increment(1),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

        } catch (error) {
            // Critical: Metrics should NEVER block or crash the main application flow
            logger.error({ error: error.message, metricName }, 'Metrics Tracking Failed');
        }
    }
}

export default MetricsService;
