import autocannon from 'autocannon';

async function runTest() {
    console.log('Starting Batch Likes Load Test...');
    const result = await autocannon({
        url: 'http://localhost:4000/api/interactions/likes/batch',
        connections: 100,
        duration: 15,
        method: 'POST',
        headers: {
            'Authorization': 'Bearer TEST_TOKEN',
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ postIds: ["id1", "id2", "id3", "id4", "id5"] })
    });
    console.log('LIKES_TEST_RESULTS_START');
    console.log(JSON.stringify(result, null, 2));
    console.log('LIKES_TEST_RESULTS_END');
}

runTest();
