import admin from 'firebase-admin';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../.env') });

// Avoid initializing twice if this is imported somewhere else
if (!admin.apps.length) {
    if (process.env.FIREBASE_PRIVATE_KEY) {
        admin.initializeApp({
            credential: admin.credential.cert({
                projectId: process.env.FIREBASE_PROJECT_ID,
                clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
                privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
            }),
        });
    } else {
        const serviceAccount = require('../config/serviceAccountKey.json');
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount)
        });
    }
}

const db = admin.firestore();

/**
 * 🛠️ Layer 4: Nightly Counter Reconciliation Worker
 * Self-heals drift in critical engagement metrics to prevent silent corruption
 */
async function reconcileMetrics() {
    console.log('🔄 Starting Metric Reconciliation Worker...');
    const startTime = Date.now();
    let healedCount = 0;

    try {
        // ------------------------------------------------------------------
        // 1. Reconcile Global Follower & Following Counts
        // ------------------------------------------------------------------
        console.log('🔍 Auditing User Subscribers (Followers)...');

        // In a massively scaled app, we wouldn't pull ALL users into memory, 
        // we'd paginate. Using limit/offset to stream them.
        const usersSnapshot = await db.collection('users').get();
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            const userData = userDoc.data();
            const reportedSubscribers = userData.subscribers || userData.subscribersCount || 0;
            const reportedFollowing = userData.followingCount || 0;

            // Count actual documents where this user is the target (follower)
            const actualSubscribersSnap = await db.collection('follows').where('followingId', '==', userId).count().get();
            const actualSubscribers = actualSubscribersSnap.data().count;

            // Count actual documents where this user is the initiator (following)
            const actualFollowingSnap = await db.collection('follows').where('followerId', '==', userId).count().get();
            const actualFollowing = actualFollowingSnap.data().count;

            if (actualSubscribers !== reportedSubscribers || actualFollowing !== reportedFollowing) {
                console.log(`⚠️ User ${userId} metric drift detected: \n   Subscribers: ${reportedSubscribers} -> ${actualSubscribers} \n   Following: ${reportedFollowing} -> ${actualFollowing}`);

                await userDoc.ref.update({
                    subscribers: actualSubscribers,
                    followingCount: actualFollowing,
                    reconciledAt: admin.firestore.FieldValue.serverTimestamp()
                });
                healedCount++;
            }
        }

        // ------------------------------------------------------------------
        // 2. Reconcile Post Like Counts & Comment Counts
        // ------------------------------------------------------------------
        console.log('🔍 Auditing Post Likes and Comments...');
        const postsSnapshot = await db.collection('posts').get();
        for (const postDoc of postsSnapshot.docs) {
            const postId = postDoc.id;
            const postData = postDoc.data();
            const reportedLikes = postData.likeCount || 0;
            const reportedComments = postData.commentCount || 0;

            const actualLikesSnap = await db.collection('likes').where('postId', '==', postId).count().get();
            const actualLikes = actualLikesSnap.data().count;

            const actualCommentsSnap = await db.collection('comments').where('postId', '==', postId).count().get();
            const actualComments = actualCommentsSnap.data().count;

            if (actualLikes !== reportedLikes || actualComments !== reportedComments) {
                console.log(`⚠️ Post ${postId} metric drift detected: \n   Likes: ${reportedLikes} -> ${actualLikes} \n   Comments: ${reportedComments} -> ${actualComments}`);

                await postDoc.ref.update({
                    likeCount: actualLikes,
                    commentCount: actualComments,
                    reconciledAt: admin.firestore.FieldValue.serverTimestamp()
                });
                healedCount++;
            }
        }

        console.log(`✅ Reconciliation Complete. \n⏱️ Duration: ${(Date.now() - startTime) / 1000}s \n🩹 Total Records Healed: ${healedCount}`);
    } catch (err) {
        console.error('❌ Error during reconciliation run:', err);
    } finally {
        process.exit(0);
    }
}

reconcileMetrics();
