import { db } from '../src/config/firebase.js';

async function removeSeedPosts() {
    console.log('Searching for seed posts (authorId: seed_bot)...');
    
    const snapshot = await db.collection('posts')
        .where('authorId', '==', 'seed_bot')
        .get();

    if (snapshot.empty) {
        console.log('No seed posts found.');
        process.exit(0);
    }

    console.log(`Found ${snapshot.size} seed posts. Deleting...`);
    
    const batchSize = 500;
    let count = 0;
    let batch = db.batch();

    for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
        count++;
        
        if (count % batchSize === 0) {
            await batch.commit();
            batch = db.batch();
            console.log(`Deleted ${count} posts...`);
        }
    }

    if (count % batchSize !== 0) {
        await batch.commit();
    }

    console.log(`Successfully removed ${count} seed posts.`);
    process.exit(0);
}

removeSeedPosts().catch(err => {
    console.error('Cleanup failed:', err);
    process.exit(1);
});
