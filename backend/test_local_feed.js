import { fetchLocalFeedWithCursor } from './src/routes/posts.js';
import { geoIndex } from './src/services/geoIndex.js';

async function run() {
    try {
        await geoIndex.build();
        console.log('Fetching Local Feed...');
        // Simulate lat/lng of Kanyakumari
        // Suppose user is on Page 3, lastDistance is 15.0 km
        
        let watchedIdsSet = new Set();
        
        // Let's pretend the user saw all Kanyakumari posts. We can't easily pass all 50 IDs,
        // but we can simulate the watchedIds by having lastDistance = 0.5. At this distance,
        // Kanyakumari posts are ~1km. If we just pass lastDistance = 2.0 and let Kanyakumari posts be filtered...
        // Actually, let's just fetch all posts first to get their IDs and add to watchedIdsSet!
        const initialRes = await fetchLocalFeedWithCursor(8.082, 77.527, 0, null, new Set(), 100);
        initialRes.data.forEach(p => watchedIdsSet.add(p.id));
        console.log('User has seen', watchedIdsSet.size, 'Kanyakumari posts.');

        const res = await fetchLocalFeedWithCursor(
            8.082, 77.527, // Kanyakumari
            initialRes.pagination.lastDistance, // lastDistance
            initialRes.pagination.lastPostId, // lastPostId
            watchedIdsSet, 
            10    // pageSize
        );
        
        console.log('Success:', res.success);
        console.log('Returned posts:', res.data.length);
        res.data.forEach(p => console.log(' ->', p.city, p.distance.toFixed(2), 'km'));
        console.log('Pagination:', res.pagination);

    } catch (e) {
        console.error('Test Failed:', e);
    }
}
run();
