import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';

async function clearAllSeeds() {
    console.log('🧹 Finding posts created by geo-seed or seed-system...');

    const seedIds = ['geo-seed', 'seed-system', 'tn-seed-20'];
    let totalDeleted = 0;

    for (const authorId of seedIds) {
        const snapshot = await db.collection('posts')
            .where('authorId', '==', authorId)
            .get();

        if (snapshot.empty) {
            console.log(`No posts found for ${authorId}.`);
            continue;
        }

        console.log(`🗑️ Deleting ${snapshot.size} posts for ${authorId}...`);

        const docs = snapshot.docs;
        for (let i = 0; i < docs.length; i += 450) {
            const chunk = docs.slice(i, i + 450);
            const batch = db.batch();
            chunk.forEach(doc => batch.delete(doc.ref));
            await batch.commit();
            console.log(`  Deleted ${chunk.length} posts...`);
        }
        totalDeleted += snapshot.size;
    }

    console.log(`✅ Cleanup complete. Total deleted: ${totalDeleted}`);
    process.exit(0);
}

clearAllSeeds().catch(err => {
    console.error('Failed to clear seed posts:', err);
    process.exit(1);
});
