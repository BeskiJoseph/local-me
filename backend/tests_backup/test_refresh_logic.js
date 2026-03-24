
import { geoIndex } from './src/services/geoIndex.js';
import logger from './src/utils/logger.js';

async function test() {
    await geoIndex.build();
    
    const lat = 13.0827; // Chennai
    const lng = 80.2707;
    
    console.log('\n--- FIRST LOAD ---');
    const result1 = geoIndex.queryLocal(lat, lng, 0, null, new Set(), null, 2);
    const seenIds = result1.posts.map(p => p.id);
    console.log('Results:', seenIds);
    
    console.log('\n--- REFRESH (WITH WATCHED IDS) ---');
    const watchedSet = new Set(seenIds);
    const result2 = geoIndex.queryLocal(lat, lng, 0, null, watchedSet, null, 2);
    console.log('Watched IDs sent:', Array.from(watchedSet));
    console.log('Results after refresh:', result2.posts.map(p => p.id));
    
    if (result1.posts[0].id === result2.posts[0].id) {
        console.error('\n❌ BUG DETECTED: Returned same posts despite watchedIds!');
    } else {
        console.log('\n✅ SUCCESS: Correctly skipped seen posts.');
    }
}

test();
