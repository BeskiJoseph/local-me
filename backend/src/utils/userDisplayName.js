export function buildDisplayName({
    displayName,
    username,
    firstName,
    lastName,
    email,
    fallback = 'User'
}) {
    const normalizedDisplayName = normalizeText(displayName);
    if (normalizedDisplayName) return normalizedDisplayName;

    const normalizedUsername = normalizeText(username);
    if (normalizedUsername) return normalizedUsername;

    const fullName = [normalizeText(firstName), normalizeText(lastName)]
        .filter(Boolean)
        .join(' ')
        .trim();
    if (fullName) return fullName;

    const emailPrefix = normalizeEmailPrefix(email);
    if (emailPrefix) return emailPrefix;

    return fallback;
}

export function normalizeText(value) {
    if (typeof value !== 'string') return '';
    const trimmed = value.trim();
    return trimmed.length ? trimmed : '';
}

function normalizeEmailPrefix(email) {
    if (typeof email !== 'string' || !email.includes('@')) return '';
    const prefix = email.split('@')[0]?.trim() || '';
    return prefix || '';
}
