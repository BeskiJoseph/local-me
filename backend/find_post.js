import { db } from './src/config/firebase.js';

async function findPost() {
    try {
        const posts = await db.collection('posts').limit(1).get();
        if (posts.empty) {
            console.log("No posts found");
        } else {
            const post = posts.docs[0];
            const data = post.data();
            const date = data.createdAt ? data.createdAt.toDate() : new Date(0);
            const ageHours = (Date.now() - date.getTime()) / 3600000;
            console.log(`REAL_POST_ID:${post.id}`);
            console.log(`AgeHours:${ageHours}`);
        }
        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
}

findPost();
