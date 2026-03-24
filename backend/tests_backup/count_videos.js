import { db } from './src/config/firebase.js';

async function countVideos() {
    const snapshot = await db.collection('posts')
        .where('mediaType', '==', 'video')
        .get();
    
    console.log(`Total video posts: ${snapshot.size}`);
    snapshot.forEach(doc => {
        const data = doc.data();
        console.log(`- ${doc.id}: ${data.title} (${data.city}, ${data.latitude}, ${data.longitude})`);
    });
    process.exit(0);
}

countVideos();
