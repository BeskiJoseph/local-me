import { db } from './src/config/firebase.js';

async function listData() {
    try {
        const posts = await db.collection('posts').limit(5).get();
        console.log(`Posts found: ${posts.size}`);
        posts.docs.forEach(doc => {
            const d = doc.data();
            console.log(`- ID: ${doc.id}, Title: ${d.title}, Status: ${d.status}, Visibility: ${d.visibility}`);
        });

        const users = await db.collection('users').limit(5).get();
        console.log(`Users found: ${users.size}`);
        users.docs.forEach(doc => {
            console.log(`- ID: ${doc.id}, Username: ${doc.data().username}`);
        });

        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
}

listData();
