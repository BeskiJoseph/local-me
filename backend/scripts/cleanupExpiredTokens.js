/**
 * Cleanup expired refresh tokens from Firestore.
 * 
 * Run manually:   node scripts/cleanupExpiredTokens.js
 * Run via cron:    0 3 * * * node /path/to/scripts/cleanupExpiredTokens.js
 * 
 * This script deletes refresh tokens that have expired (based on `expiresAt`)
 * or that were revoked more than 7 days ago.
 */

import '../src/config/env.js';
import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';

const BATCH_SIZE = 500;
const SEVEN_DAYS_AGO = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
const NOW = new Date().toISOString();

async function deleteInBatches(query, label) {
    let totalDeleted = 0;

    while (true) {
        const snapshot = await query.limit(BATCH_SIZE).get();
        if (snapshot.empty) break;

        const batch = db.batch();
        snapshot.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();

        totalDeleted += snapshot.size;
        console.log(`  Deleted ${totalDeleted} ${label} tokens so far...`);
    }

    return totalDeleted;
}

async function main() {
    console.log('🧹 Refresh Token Cleanup');
    console.log(`   Now: ${NOW}`);
    console.log('');

    // 1. Delete expired tokens
    const expiredQuery = db.collection('refresh_tokens')
        .where('expiresAt', '<', NOW);
    const expiredCount = await deleteInBatches(expiredQuery, 'expired');
    console.log(`✅ Deleted ${expiredCount} expired tokens.`);

    // 2. Delete old revoked tokens (revoked > 7 days ago)
    const revokedQuery = db.collection('refresh_tokens')
        .where('isRevoked', '==', true)
        .where('createdAt', '<', SEVEN_DAYS_AGO);
    const revokedCount = await deleteInBatches(revokedQuery, 'revoked');
    console.log(`✅ Deleted ${revokedCount} old revoked tokens.`);

    console.log('');
    console.log(`🎉 Cleanup complete. Total removed: ${expiredCount + revokedCount}`);
    process.exit(0);
}

main().catch(err => {
    console.error('❌ Cleanup failed:', err);
    process.exit(1);
});
