import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';

async function testQuery() {
    console.log('🧪 Testing local feed query...');
    const prefix = 't9z'; // Madurai area
    try {
        const snapshot = await db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .where('geoHash', '>=', prefix)
            .where('geoHash', '<=', prefix + '\uf8ff')
            .orderBy('geoHash')
            .orderBy('createdAt', 'desc')
            .limit(10)
            .get();

        console.log(`✅ Query successful! Found ${snapshot.size} posts.`);
        snapshot.docs.forEach(doc => console.log(` - ${doc.id} | ${doc.data().geoHash}`));
    } catch (err) {
        console.error('❌ Query failed:', err.message);
        if (err.message.includes('index')) {
            console.log('💡 This confirms the index is missing or building.');
        }
    }
    process.exit(0);
}

testQuery().catch(err => {
    console.error(err);
    process.exit(1);
});
