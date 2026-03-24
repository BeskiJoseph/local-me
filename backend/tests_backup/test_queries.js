import { db } from './src/config/firebase.js';

async function testGlobal() {
    try {
        console.log('Testing Global Query...');
        let trendingQuery = db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .orderBy('engagementScore', 'desc')
            .limit(5);

        const snapshot = await trendingQuery.get();
        console.log('Global Query OK. Returning', snapshot.size, 'posts:');
        snapshot.docs.forEach(d => console.log(' ->', d.id, d.data().title, 'Score:', d.data().engagementScore));
    } catch (e) {
        console.error('Global Query FAILED:', e.message);
    }
}

async function testLocal() {
    try {
        console.log('Testing Local Query...');
        let localQuery = db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .where('geoHash', '>=', 't')
            .where('geoHash', '<=', 't' + '\uf8ff')
            .orderBy('geoHash')
            .orderBy('engagementScore', 'desc')
            .limit(5);

        const snapshot = await localQuery.get();
        console.log('Local Query OK. Returning', snapshot.size, 'posts:');
        snapshot.docs.forEach(d => console.log(' ->', d.id, d.data().title, 'Score:', d.data().engagementScore));
    } catch (e) {
        console.error('Local Query FAILED:', e.message);
    }
}

async function main() {
    await testGlobal();
    await testLocal();
    process.exit(0);
}

main();
