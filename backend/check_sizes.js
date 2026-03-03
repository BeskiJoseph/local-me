import { db } from './src/config/firebase.js';

async function checkSizes() {
    try {
        const posts = await db.collection('posts').count().get();
        const likes = await db.collection('likes').count().get();
        const follows = await db.collection('follows').count().get();

        console.log(`TOTALS:`);
        console.log(`Posts: ${posts.data().count}`);
        console.log(`Likes: ${likes.data().count}`);
        console.log(`Follows: ${follows.data().count}`);
        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
}

checkSizes();
