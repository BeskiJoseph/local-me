import admin from 'firebase-admin';
import dotenv from 'dotenv';
import logger from '../utils/logger.js';

dotenv.config();

const requiredEnvVars = [
    'FIREBASE_PROJECT_ID',
    'FIREBASE_PRIVATE_KEY',
    'FIREBASE_CLIENT_EMAIL',
];

const missingVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingVars.length) {
    logger.error('❌ Missing required environment variables: %s', missingVars.join(', '));
    process.exit(1);
}

try {
    admin.initializeApp({
        credential: admin.credential.cert({
            projectId: process.env.FIREBASE_PROJECT_ID,
            privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
            clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        }),
    });
    logger.info('✅ Firebase Admin initialized with Service Account');
} catch (error) {
    logger.error('Failed to initialize Firebase Admin: %s', error.message);
    process.exit(1);
}

const firestore = admin.firestore();
firestore.settings({ ignoreUndefinedProperties: true });
export const db = firestore;
export const auth = admin.auth();
export default admin;
