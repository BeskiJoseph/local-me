import { db } from './src/config/firebase.js';

async function listData() {
    try {
        const posts = await db.collection('posts').limit(10).get();
        console.log(`Posts found: ${posts.size}`);
        posts.docs.forEach(doc => {
            const d = doc.data();
            console.log(`- ID: ${doc.id}`);
            console.log(`  Title: "${d.title}"`);
            console.log(`  Status: "${d.status}"`);
            console.log(`  Visibility: "${d.visibility}"`);
            console.log(`  AuthorId: "${d.authorId}"`);
            console.log(`  CreatedAt: ${d.createdAt ? d.createdAt.toDate() : 'null'}`);
        });

        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
}

listData();
