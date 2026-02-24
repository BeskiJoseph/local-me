import xss from 'xss';

/**
 * Very strict XSS whitelist (empty means no HTML tags are allowed at all).
 * Strip any ignore tags completely to prevent <script>bodies</script> from remaining as text.
 */
const xssOptions = {
    whiteList: {}, // Empty means NO tags allowed
    stripIgnoreTag: true,
    stripIgnoreTagBody: ['script', 'style', 'xml', 'iframe']
};
const myXss = new xss.FilterXSS(xssOptions);

/**
 * Filter object to only include allowed keys (Mass Assignment Defense)
 * @param {Object} obj raw incoming payload from req.body
 * @param {Array<string>} allowed array of allowed string keys
 * @returns {Object} cleaned object containing only allowed keys
 */
export function pickAllowedFields(obj, allowed) {
    if (!obj || typeof obj !== 'object') return {};
    return Object.keys(obj).reduce((acc, key) => {
        if (allowed.includes(key)) {
            acc[key] = obj[key];
        }
        return acc;
    }, {});
}

/**
 * Recursively sanitize all strings in an object/array/value against XSS
 * @param {any} input mixed data structure to sanitize
 * @returns {any} identical structure with strings sanitized
 */
export function sanitizeInput(input) {
    if (typeof input === 'string') {
        const sanitized = myXss.process(input);
        // Special case: if processing empties it, but it wasn't empty, it was pure malice
        return sanitized.trim();
    }
    if (Array.isArray(input)) {
        return input.map(item => sanitizeInput(item));
    }
    if (input !== null && typeof input === 'object') {
        return Object.keys(input).reduce((acc, key) => {
            acc[key] = sanitizeInput(input[key]);
            return acc;
        }, {});
    }
    return input;
}

/**
 * Strict combination method to protect incoming req.body 
 * Applies Mass Assignment shield THEN structural XSS sanitization
 * @param {Object} obj raw incoming request body
 * @param {Array<string>} allowedFields strict list of permitted keys
 * @returns {Object} Fortified clean payload
 */
export function cleanPayload(obj, allowedFields) {
    const picked = pickAllowedFields(obj, allowedFields);
    return sanitizeInput(picked);
}
