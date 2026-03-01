import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';

async function checkPosts() {
    console.log('🔍 Checking first 5 posts for geoHash field...');
    const snapshot = await db.collection('posts').limit(5).get();

    if (snapshot.empty) {
        console.log('❌ No posts found in collection!');
        process.exit(0);
    }

    snapshot.docs.forEach((doc, i) => {
        const d = doc.data();
        console.log(`P${i + 1}|ID:${doc.id}|GH:${d.geoHash}|City:${d.city}`);
    });

    process.exit(0);
}

checkPosts().catch(err => {
    console.error(err);
    process.exit(1);
});
