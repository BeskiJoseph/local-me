import dotenv from 'dotenv';
import logger from '../utils/logger.js';

dotenv.config();

const config = {
    port: process.env.PORT || 4000,
    nodeEnv: process.env.NODE_ENV || 'development',
    corsOrigin: process.env.CORS_ALLOWED_ORIGINS || '*',
    firebase: {
        projectId: process.env.FIREBASE_PROJECT_ID,
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    },
    r2: {
        accountId: process.env.R2_ACCOUNT_ID,
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
        bucketName: process.env.R2_BUCKET_NAME || 'localme',
        publicBaseUrl: process.env.R2_PUBLIC_BASE_URL,
    },
};

// Simple isolation check
if (config.nodeEnv === 'production') {
    logger.info('🚀 Running in PRODUCTION mode');
    // Add production-only checks/constraints here
}

export default config;
