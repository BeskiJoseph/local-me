const admin = require('firebase-admin');
admin.initializeApp();

const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');

// --- OTP Functions ---
const { sendEmailOtp, verifyEmailOtp } = require('./otp');
exports.sendEmailOtp = sendEmailOtp;
exports.verifyEmailOtp = verifyEmailOtp;


// --- Likes counter: posts/{postId}/likes/{userId} ---
exports.onLikeCreated = onDocumentCreated('posts/{postId}/likes/{userId}', async (event) => {
  const { postId } = event.params;
  const postRef = admin.firestore().doc(`posts/${postId}`);
  await postRef.set(
    { likeCount: admin.firestore.FieldValue.increment(1) },
    { merge: true }
  );
});

exports.onLikeDeleted = onDocumentDeleted('posts/{postId}/likes/{userId}', async (event) => {
  const { postId } = event.params;
  const postRef = admin.firestore().doc(`posts/${postId}`);

  // Clamp at >= 0
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(postRef);
    if (!snap.exists) return;
    const current = (snap.get('likeCount') || 0);
    const next = Math.max(0, current - 1);
    tx.update(postRef, { likeCount: next });
  });
});

// --- Comments counter: posts/{postId}/comments/{commentId} ---
exports.onCommentCreated = onDocumentCreated('posts/{postId}/comments/{commentId}', async (event) => {
  const { postId } = event.params;
  const postRef = admin.firestore().doc(`posts/${postId}`);
  await postRef.set(
    { commentCount: admin.firestore.FieldValue.increment(1) },
    { merge: true }
  );
});

exports.onCommentDeleted = onDocumentDeleted('posts/{postId}/comments/{commentId}', async (event) => {
  const { postId } = event.params;
  const postRef = admin.firestore().doc(`posts/${postId}`);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(postRef);
    if (!snap.exists) return;
    const current = (snap.get('commentCount') || 0);
    const next = Math.max(0, current - 1);
    tx.update(postRef, { commentCount: next });
  });
});

// --- Subscribers counter: users/{userId}/followers/{followerId} ---
exports.onFollowerCreated = onDocumentCreated('users/{userId}/followers/{followerId}', async (event) => {
  const { userId } = event.params;
  const userRef = admin.firestore().doc(`users/${userId}`);
  await userRef.set(
    { subscribers: admin.firestore.FieldValue.increment(1) },
    { merge: true }
  );
});

exports.onFollowerDeleted = onDocumentDeleted('users/{userId}/followers/{followerId}', async (event) => {
  const { userId } = event.params;
  const userRef = admin.firestore().doc(`users/${userId}`);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) return;
    const current = (snap.get('subscribers') || 0);
    const next = Math.max(0, current - 1);
    tx.update(userRef, { subscribers: next });
  });
});

// --- Contents counter: posts/{postId} created/deleted ---
exports.onPostCreated = onDocumentCreated('posts/{postId}', async (event) => {
  const data = event.data?.data();
  const authorId = data?.authorId;
  if (!authorId) return;

  const userRef = admin.firestore().doc(`users/${authorId}`);
  await userRef.set(
    { contents: admin.firestore.FieldValue.increment(1) },
    { merge: true }
  );
});

exports.onPostDeleted = onDocumentDeleted('posts/{postId}', async (event) => {
  const data = event.data?.data();
  const authorId = data?.authorId;
  if (!authorId) return;

  const userRef = admin.firestore().doc(`users/${authorId}`);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) return;
    const current = (snap.get('contents') || 0);
    const next = Math.max(0, current - 1);
    tx.update(userRef, { contents: next });
  });
});


