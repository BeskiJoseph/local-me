import { db } from '../src/config/firebase.js';

async function migrate() {
    console.log('🚀 Starting Search Field Migration...');

    // 1. Migrate Users
    console.log('\n👤 Migrating Users...');
    const usersSnap = await db.collection('users').get();
    console.log(`Found ${usersSnap.size} users.`);

    let userCount = 0;
    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const update = {};

        if (data.displayName && !data.displayName_lowercase) {
            update.displayName_lowercase = data.displayName.toLowerCase();
        }
        if (data.firstName && !data.firstName_lowercase) {
            update.firstName_lowercase = data.firstName.toLowerCase();
        }
        if (data.lastName && !data.lastName_lowercase) {
            update.lastName_lowercase = data.lastName.toLowerCase();
        }
        if (data.username && data.username !== data.username.toLowerCase()) {
            update.username = data.username.toLowerCase();
        }

        if (Object.keys(update).length > 0) {
            await doc.ref.update(update);
            userCount++;
        }
    }
    console.log(`✅ Updated ${userCount} users.`);

    // 2. Migrate Posts
    console.log('\n📝 Migrating Posts...');
    const postsSnap = await db.collection('posts').get();
    console.log(`Found ${postsSnap.size} posts.`);

    let postCount = 0;
    for (const doc of postsSnap.docs) {
        const data = doc.data();
        const update = {};

        const title = data.title || '';
        const body = data.body || data.text || '';

        if (!data.title_lowercase) {
            update.title_lowercase = title.toLowerCase();
        }
        if (!data.body_lowercase) {
            update.body_lowercase = body.toLowerCase();
        }

        if (Object.keys(update).length > 0) {
            await doc.ref.update(update);
            postCount++;
        }
    }
    console.log(`✅ Updated ${postCount} posts.`);

    console.log('\n✨ Migration Complete!');
    process.exit(0);
}

migrate().catch(err => {
    console.error('❌ Migration failed:', err);
    process.exit(1);
});
