import { db } from './src/config/firebase.js';

async function checkPost() {
    try {
        const post = await db.collection('posts').doc('5RcTsZj4ZVcx7').get();
        if (post.exists) {
            const data = post.data();
            const date = data.createdAt.toDate();
            const ageHours = (Date.now() - date.getTime()) / 3600000;
            console.log(`Post: ${post.id}`);
            console.log(`CreatedAt: ${date}`);
            console.log(`Age in hours: ${ageHours}`);
        } else {
            console.log("Post not found");
        }
        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
}

checkPost();
