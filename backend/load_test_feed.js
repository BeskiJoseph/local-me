import autocannon from 'autocannon';

async function runTest() {
    // You will need to replace this with a real Firebase ID token or Custom JWT from your flutter app.
    // To get one quickly, print it to the console in your Flutter app after logging in:
    // console.log(await FirebaseAuth.instance.currentUser?.getIdToken());
    const TOKEN = 'REPLACE_ME_WITH_REAL_TOKEN';

    if (TOKEN === 'REPLACE_ME_WITH_REAL_TOKEN') {
        console.warn('⚠️ WARNING: You are using a placeholder token. The request will likely 401 Unauthorized.');
        console.warn('Please replace TOKEN in load_test_feed.js with a valid auth token to get accurate timing.');
    }

    console.log('Starting Feed Load Test...');
    console.log('Testing GET /api/posts?feedType=local&lat=37.77&lng=-122.41');

    // Test parameters
    const url = 'http://localhost:4000/api/posts?feedType=local&lat=37.77&lng=-122.41';

    const instance = autocannon({
        url,
        connections: 20, // 20 concurrent users hitting the feed
        duration: 10,   // test for 10 seconds
        method: 'GET',
        headers: {
            'Authorization': `Bearer ${TOKEN}`,
            'Content-Type': 'application/json'
        }
    });

    autocannon.track(instance, { renderProgressBar: true });

    instance.on('done', (result) => {
        console.log('\n========================================');
        console.log('📊 TEST RESULTS');
        console.log('========================================');
        console.log(`Requests/sec:  ${result.requests.average}`);
        console.log(`Latency (avg): ${result.latency.average} ms`);
        console.log(`Latency (p99): ${result.latency.p99} ms`);
        console.log(`Total Req:     ${result.requests.total}`);
        console.log(`Errors/Timeouts: ${result.errors} / ${result.timeouts}`);
        console.log(`Non-200 Responses: ${result.non2xx}`);
        console.log('========================================\n');

        if (result.non2xx > 0) {
            console.log('⚠️ Note: You had non-200 responses. Make sure your TOKEN is valid.');
        }
    });
}

runTest();
