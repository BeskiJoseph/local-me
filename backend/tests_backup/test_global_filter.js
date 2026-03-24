
const sampleCachedPosts = [
    { id: 'p1', authorId: 'a1', title: 'Post 1' },
    { id: 'p2', authorId: 'a2', title: 'Post 2' },
    { id: 'p3', authorId: 'a3', title: 'Post 3' }
];

const watchedIds = 'p1, p2';
const watchedIdsSet = new Set(watchedIds.split(',').map(id => id.trim()).filter(Boolean));

console.log('Watched Set Size:', watchedIdsSet.size);
console.log('Set contents:', Array.from(watchedIdsSet));

const finalPosts = sampleCachedPosts.filter(
    post => !watchedIdsSet.has(post.id)
);

console.log('Filtered Results:', finalPosts.map(p => p.id));

if (finalPosts.length === 1 && finalPosts[0].id === 'p3') {
    console.log('\n✅ SUCCESS: Global filter works.');
} else {
    console.error('\n❌ FAILURE: Global filter failed.');
}
