const SPAM_KEYWORDS = ['spam', 'buy bitcoin', 'free followers', 'click here'];

export const filterContent = (text) => {
    if (!text) return true;
    const lowerText = text.toLowerCase();
    for (const keyword of SPAM_KEYWORDS) {
        if (lowerText.includes(keyword)) {
            return false;
        }
    }
    return true;
};
