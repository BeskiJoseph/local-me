import { geoIndex } from '../src/services/geoIndex.js';
import logger from '../src/utils/logger.js';
import admin from 'firebase-admin';

// Initialize Firebase for the script if not already initialized
// In a real environment, you might need to provide service account JSON
// but here we assume the environment already has it or it's provided in src/config/firebase.js

async function runTest() {
    console.log('[TEST] Starting GeoIndex backfill and query test...');

    // 1. Build Index
    const startBuild = Date.now();
    await geoIndex.build();
    console.log('[TEST] Index build took ' + (Date.now() - startBuild) + 'ms');
    console.log('[TEST] Final Index size: ' + geoIndex.size);

    if (geoIndex.size === 0) {
        console.warn('[TEST] Index is empty. Make sure you have active/public posts in Firestore with valid coordinates.');
        process.exit(0);
    }

    // 2. Test Query from Kumbakonam (10.9601, 79.3788)
    const KUMBAKONAM = { lat: 10.9601, lng: 79.3788 };
    console.log(`[TEST] Querying from Kumbakonam ${JSON.stringify(KUMBAKONAM)}...`);

    const startQuery = Date.now();
    const results = geoIndex.query({
        userLat: KUMBAKONAM.lat,
        userLng: KUMBAKONAM.lng,
        lastDistance: 0,
        lastPostId: null,
        watchedIdsSet: new Set(),
        limit: 10
    });

    console.log(`[TEST] Query took ${Date.now() - startQuery}ms`);

    if (results.length === 0) {
        console.log('[TEST] No results found.');
    } else {
        console.log('[TEST] Results:');
        results.forEach((r, i) => {
            console.log(`${i + 1}. Post: ${r.postId} | Distance: ${r.distance.toFixed(4)}km`);
        });

        // 3. Verify order
        let isOrdered = true;
        for (let i = 1; i < results.length; i++) {
            if (results[i].distance < results[i - 1].distance) {
                isOrdered = false;
                break;
            }
        }
        console.log(`[TEST] Strict distance order verified: ${isOrdered ? '✅ YES' : '❌ NO'}`);
    }

    process.exit(0);
}

runTest().catch(err => {
    console.error('[TEST] ❌ Test failed:', err);
    process.exit(1);
});
