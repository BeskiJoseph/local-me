async function test() {
    const rawUrl = 'https%3A%2F%2Fmedia-proxy.beskijosphjr.workers.dev%2Fposts%2FkwDX89bhAcaa1qVABrSPiX0Dypt1%2FkwDX89bhAcaa1qVABrSPiX0Dypt1_1774117195571%2Fimages%2F6548b6a1-843f-4e9f-bae0-1910c4eef9bf.jpg';
    try {
        const decodedUrl = decodeURIComponent(rawUrl);
        const parsedUrl = new URL(decodedUrl);
        
        console.log('Testing global fetch with proxy parameters for:', parsedUrl.toString());
        
        const res = await fetch(parsedUrl.toString(), {
            headers: { 'User-Agent': 'LocalMe-Backend-Proxy/1.0' },
            signal: AbortSignal.timeout(15000),
        });
        
        console.log('Status:', res.status);
        console.log('OK:', res.ok);
    } catch (err) {
        console.error('Fetch failed:', err.name, '-', err.message);
    }
}

test();
