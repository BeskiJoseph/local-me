import admin from 'firebase-admin';
import dotenv from 'dotenv';

dotenv.config();

// ============================================
// ENV VALIDATION
// ============================================
const requiredEnvVars = [
    'FIREBASE_PROJECT_ID',
    'FIREBASE_PRIVATE_KEY',
    'FIREBASE_CLIENT_EMAIL',
    'R2_ACCOUNT_ID',
    'R2_ACCESS_KEY_ID',
    'R2_SECRET_ACCESS_KEY',
    'R2_PUBLIC_BASE_URL',
];

const missingVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingVars.length) {
    console.error('❌ Missing required environment variables:', missingVars.join(', '));
    process.exit(1);
}

// ============================================
// FIREBASE ADMIN INITIALIZATION
// ============================================
admin.initializeApp({
    credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    }),
});

console.log('✅ Firebase Admin initialized');

// ============================================
// CONFIGURATION EXPORT
// ============================================
export const config = {
    port: process.env.PORT || 4000,
    nodeEnv: process.env.NODE_ENV || 'development',
    corsOrigin: process.env.CORS_ORIGIN || '*',
    r2: {
        accountId: process.env.R2_ACCOUNT_ID,
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
        bucketName: process.env.R2_BUCKET_NAME || 'localme',
        publicBaseUrl: process.env.R2_PUBLIC_BASE_URL,
    },
};

export default config;
