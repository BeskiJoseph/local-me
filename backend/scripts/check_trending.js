import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';

function computeTrendingScore(post, gravity = 1.4) {
    const likes = post.likeCount || 0;
    const comments = post.commentCount || 0;
    const views = post.viewCount || 0;
    const engagement = (likes * 5) + (comments * 10) + (views * 0.5) + 1;
    let ageHours = 0;
    if (post.createdAt) {
        const createdMs = post.createdAt.toDate().getTime();
        ageHours = (Date.now() - createdMs) / 3600000;
    }
    const age = Math.max(ageHours, 0.5);
    return engagement / Math.pow(age + 2, gravity);
}

async function checkTrending() {
    console.log('📈 Checking Top Trending Posts...');
    const snapshot = await db.collection('posts')
        .where('visibility', '==', 'public')
        .where('status', '==', 'active')
        .orderBy('createdAt', 'desc')
        .limit(100)
        .get();

    let posts = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }))
        .map(post => ({
            ...post,
            score: computeTrendingScore(post)
        }));

    posts.sort((a, b) => b.score - a.score);

    console.log('Rank | Score | Likes | Age (h) | Title');
    console.log('---------------------------------------');
    posts.slice(0, 10).forEach((p, i) => {
        const age = ((Date.now() - p.createdAt.toDate().getTime()) / 3600000).toFixed(2);
        console.log(`${i + 1} | ${p.score.toFixed(3)} | ${p.likeCount || 0} | ${age}h | ${p.title}`);
    });

    process.exit(0);
}

checkTrending().catch(err => {
    console.error(err);
    process.exit(1);
});
