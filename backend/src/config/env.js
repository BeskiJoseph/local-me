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

// Production validation
if (config.nodeEnv === 'production') {
    logger.info('🚀 Running in PRODUCTION mode');
    
    // Critical security checks for production
    const requiredEnvVars = [
        'FIREBASE_PROJECT_ID',
        'FIREBASE_PRIVATE_KEY', 
        'FIREBASE_CLIENT_EMAIL',
        'JWT_ACCESS_SECRET',
        'R2_ACCOUNT_ID',
        'R2_ACCESS_KEY_ID',
        'R2_SECRET_ACCESS_KEY'
    ];
    
    const missing = requiredEnvVars.filter(varName => !process.env[varName]);
    if (missing.length > 0) {
        logger.error(`❌ Missing required production environment variables: ${missing.join(', ')}`);
        process.exit(1);
    }
    
    // Security warnings
    if (config.corsOrigin === '*') {
        logger.warn('⚠️  CORS is set to allow all origins (*). This is insecure for production!');
    }
    
    if (!process.env.CORS_ALLOWED_ORIGINS) {
        logger.warn('⚠️  CORS_ALLOWED_ORIGINS not set. Using default which may be insecure.');
    }
}

export default config;
