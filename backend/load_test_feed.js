import autocannon from 'autocannon';

async function runTest() {
    console.log('Starting Feed Load Test...');
    const result = await autocannon({
        url: 'http://localhost:4000/api/posts?limit=20',
        connections: 100,
        duration: 15,
        headers: {
            'Authorization': 'Bearer TEST_TOKEN'
        }
    });
    console.log('FEED_TEST_RESULTS_START');
    console.log(JSON.stringify(result, null, 2));
    console.log('FEED_TEST_RESULTS_END');
}

runTest();
