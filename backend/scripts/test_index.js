import { db } from '../src/config/firebase.js';

async function testQuery() {
    console.log('🧪 Testing Firestore geo-priority query...');
    try {
        const ringPrefix = 'tf346'; // Chennai local
        const snapshot = await db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .where('geoHash', '>=', ringPrefix)
            .where('geoHash', '<=', ringPrefix + '\uf8ff')
            .orderBy('geoHash')
            .orderBy('createdAt', 'desc')
            .limit(1)
            .get();

        console.log(`✅ Success! Found ${snapshot.size} posts.`);
    } catch (err) {
        console.error('❌ Query failed:', err.message);
        if (err.message.includes('index')) {
            console.log('\n🔗 You need to create this index:');
            console.log('https://console.firebase.google.com/project/YOUR_PROJECT/firestore/indexes');
        }
    }
    process.exit(0);
}

testQuery();
