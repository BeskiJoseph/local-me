# Security Policy

## Reporting Security Issues

If you discover a security vulnerability in this project, please report it by emailing the project maintainer. **Do not create a public GitHub issue.**

---

## Security Best Practices

### 1. Environment Variables

**NEVER commit sensitive credentials to the repository:**

- ❌ `.env` files
- ❌ `serviceAccountKey.json`
- ❌ API keys, tokens, or passwords
- ❌ Private keys

**Always use:**
- ✅ `.env.example` templates with placeholder values
- ✅ Environment variables in production
- ✅ Secrets management in CI/CD pipelines

### 2. Credential Rotation

If credentials are accidentally exposed:

1. **Immediately rotate all exposed credentials:**
   - Firebase service account keys
   - Cloudflare R2 access keys
   - Google OAuth client secrets
   - Any other API keys

2. **Remove from repository history:**
   ```bash
   # Use git-filter-repo or BFG Repo-Cleaner
   git filter-repo --path backend/.env --invert-paths
   ```

3. **Update all deployment environments** with new credentials

### 3. Firebase Security

**Firestore Security Rules:**
- Rules are deployed in `firestore.rules`
- Test rules before deploying to production
- Never use `allow read, write: if true` in production

**Firebase Admin SDK:**
- Only use on trusted backend servers
- Never expose admin credentials to client apps
- Use service accounts with minimal required permissions

### 4. API Security

**Backend Security:**
- All upload endpoints require Firebase authentication
- Rate limiting enabled on sensitive endpoints
- File size and type validation enforced
- CORS configured for production domains only

**Client Security:**
- Never store secrets in client code
- Use environment variables for configuration
- Validate all user input before submission

### 5. Production Deployment

**Before deploying to production:**

- [ ] All `.env` files removed from repository
- [ ] `.gitignore` properly configured
- [ ] All credentials rotated if previously exposed
- [ ] Environment variables set in hosting platform
- [ ] CORS configured for production domains
- [ ] Firestore security rules deployed
- [ ] HTTPS enabled on all endpoints
- [ ] Error messages don't expose sensitive information

---

## Secure Configuration Guide

### Backend (.env)

```env
# ✅ Good: Use environment variables
FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID}
R2_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID}

# ❌ Bad: Hardcoded values
FIREBASE_PROJECT_ID=my-project-123
R2_ACCESS_KEY_ID=abc123secretkey
```

### Flutter App

```bash
# ✅ Good: Use --dart-define
flutter build apk --dart-define=API_URL=https://api.example.com

# ❌ Bad: Hardcoded in source code
static const apiUrl = 'https://api.example.com';
```

---

## Security Checklist

### Development
- [ ] Use `.env.example` templates
- [ ] Never commit `.env` files
- [ ] Test with development credentials
- [ ] Use localhost for local testing

### Staging
- [ ] Use separate staging credentials
- [ ] Test security rules
- [ ] Verify authentication flows
- [ ] Check error handling

### Production
- [ ] Rotate all credentials
- [ ] Use production Firebase project
- [ ] Enable rate limiting
- [ ] Configure CORS properly
- [ ] Enable HTTPS only
- [ ] Set up monitoring and alerts
- [ ] Regular security audits

---

## Incident Response

If a security breach occurs:

1. **Contain**: Immediately revoke compromised credentials
2. **Assess**: Determine scope of exposure
3. **Remediate**: Rotate all potentially affected credentials
4. **Notify**: Inform affected users if necessary
5. **Review**: Update security practices to prevent recurrence

---

## Contact

For security concerns, contact: [Your security contact email]

---

## Updates

This security policy is reviewed and updated regularly. Last updated: 2026-02-05
