# Testing Guide - Backend & Flutter Integration

## 🧪 Quick Start Testing

### 1. Test Backend Locally (5 minutes)

**Start the backend:**
```powershell
cd "c:\Users\beski\Downloads\testpro-main (1)\backend"
npm start
```

**Expected Output:**
```
✅ Firebase Admin initialized
🚀 Server running on port 4000
🌐 Environment: development
🔒 CORS: *
📦 Media base: https://media-proxy.beskijosphjr.workers.dev
```

---

### 2. Test Health Endpoint

**Open new PowerShell window:**
```powershell
# Test health endpoint
Invoke-WebRequest -Uri "http://localhost:4000/health" -Method GET | Select-Object -ExpandProperty Content
```

**Expected Response:**
```json
{
  "status": "ok",
  "time": "2026-02-05T...",
  "uptime": 123
}
```

---

### 3. Test Security Headers

```powershell
# Check security headers
Invoke-WebRequest -Uri "http://localhost:4000/health" -Method GET | Select-Object -ExpandProperty Headers
```

**Expected Headers:**
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Strict-Transport-Security: max-age=31536000`
- `Content-Security-Policy: default-src 'self'`

---

### 4. Test Rate Limiting

```powershell
# Test rate limiting (should block after 60 requests/min)
1..65 | ForEach-Object {
    Invoke-WebRequest -Uri "http://localhost:4000/health" -Method GET
    Write-Host "Request $_"
}
```

**Expected:** After 60 requests, you should get:
```json
{
  "error": "Too many requests, please try again later."
}
```

---

### 5. Test Flutter App with Backend

**Hot reload the Flutter app:**
1. In your Flutter terminal, press `r` to hot reload
2. The app will now use `http://localhost:4000`

**Test Upload Flow:**

1. **Sign in with Google:**
   - Open the app
   - Click "Sign in with Google"
   - Complete authentication
   - **Watch backend logs** for authentication request

2. **Upload Profile Image:**
   - Go to your profile
   - Click "Edit Profile" or profile image
   - Select an image
   - Upload
   - **Watch backend logs** for upload request

3. **Create Post with Media:**
   - Click "New Post"
   - Add title and content
   - Attach image/video
   - Submit
   - **Watch backend logs** for upload request

---

## 📊 Backend Logs to Watch For

When you perform actions, you should see logs like:

**Authentication Request:**
```
2026-02-05 15:52:00 [info]: Request completed {
  method: 'POST',
  url: '/api/upload/profile',
  status: 200,
  duration: '45ms',
  ip: '::1',
  userAgent: 'Dart/...'
}
```

**Successful Upload:**
```
2026-02-05 15:52:05 [info]: Profile image uploaded {
  userId: 'abc123...',
  key: 'profile-images/abc123.../uuid.jpg',
  size: 123456
}
```

**Rate Limit Violation:**
```
2026-02-05 15:52:10 [warn]: SECURITY_EVENT {
  event: 'RATE_LIMIT_EXCEEDED',
  ip: '::1',
  path: '/api/upload/profile'
}
```

**Validation Error:**
```
2026-02-05 15:52:15 [warn]: SECURITY_EVENT {
  event: 'VALIDATION_FAILED',
  ip: '::1',
  path: '/api/upload/profile',
  errors: [...]
}
```

---

## 🔒 Security Feature Tests

### Test 1: Invalid File Type

**Try uploading a .txt file as an image:**
- Expected: `400 Bad Request` - "File type does not match declared media type"
- Backend log: `FILE_TYPE_MISMATCH` security event

### Test 2: Missing Authentication

**Try uploading without token:**
```powershell
Invoke-WebRequest -Uri "http://localhost:4000/api/upload/profile" -Method POST
```
- Expected: `401 Unauthorized` - "No token provided"
- Backend log: `MISSING_AUTH_TOKEN` security event

### Test 3: Expired Token

**Use an old/invalid token:**
- Expected: `401 Unauthorized` - "Invalid or expired token"
- Backend log: `AUTH_VERIFICATION_FAILED` security event

### Test 4: File Too Large

**Try uploading a file > 10MB:**
- Expected: `413 Request Entity Too Large`
- Backend log: `REQUEST_TOO_LARGE` security event

### Test 5: Rate Limiting

**Upload 25 files rapidly:**
- Expected: After 20 uploads, `429 Too Many Requests`
- Backend log: `UPLOAD_RATE_LIMIT_EXCEEDED` security event

---

## 🎯 Integration Test Checklist

### Backend Tests
- [ ] Health endpoint responds
- [ ] Security headers present
- [ ] Rate limiting works
- [ ] Authentication required
- [ ] File validation works
- [ ] Logs are generated
- [ ] Errors are handled gracefully

### Flutter App Tests
- [ ] App connects to backend
- [ ] Google Sign-In works
- [ ] Profile image upload works
- [ ] Post media upload works
- [ ] Error messages display correctly
- [ ] Loading states work
- [ ] Images display after upload

### Security Tests
- [ ] Invalid file types rejected
- [ ] Missing auth token rejected
- [ ] Expired token rejected
- [ ] Large files rejected
- [ ] Rate limiting triggers
- [ ] Security events logged
- [ ] No stack traces in errors

---

## 🐛 Troubleshooting

### Backend Won't Start

**Error:** `Missing required environment variables`
- **Fix:** Check `backend/.env` has all variables from `.env.example`

**Error:** `Firebase initialization failed`
- **Fix:** Verify `FIREBASE_PRIVATE_KEY` has `\n` characters preserved

**Error:** `Port 4000 already in use`
- **Fix:** Kill existing process or change PORT in `.env`

### Flutter Can't Connect

**Error:** `Failed to connect to localhost:4000`
- **Fix:** Ensure backend is running
- **Fix:** Check firewall isn't blocking port 4000
- **Fix:** Try `http://127.0.0.1:4000` instead of `localhost`

**Error:** `CORS error`
- **Fix:** Ensure `CORS_ORIGIN=*` in backend `.env` for development

### Upload Fails

**Error:** `401 Unauthorized`
- **Fix:** Ensure user is signed in
- **Fix:** Check Firebase token is valid

**Error:** `400 Bad Request - File type mismatch`
- **Fix:** Ensure file is actually an image/video
- **Fix:** Check file extension matches content

**Error:** `500 Internal Server Error`
- **Fix:** Check backend logs for detailed error
- **Fix:** Verify R2 credentials are correct

---

## 📈 Performance Testing

### Load Test Backend

```powershell
# Install Apache Bench (optional)
# Or use this simple PowerShell loop

# Test 100 requests
1..100 | ForEach-Object {
    $start = Get-Date
    Invoke-WebRequest -Uri "http://localhost:4000/health" -Method GET | Out-Null
    $duration = (Get-Date) - $start
    Write-Host "Request $_ : $($duration.TotalMilliseconds)ms"
}
```

**Expected Performance:**
- Average response time: < 50ms
- No errors under load
- Rate limiting kicks in appropriately

---

## ✅ Production Testing (After Deployment)

### Test Deployed Backend

```powershell
# Replace with your actual backend URL
$backendUrl = "https://your-backend.onrender.com"

# Health check
Invoke-WebRequest -Uri "$backendUrl/health" -Method GET

# Check security headers
Invoke-WebRequest -Uri "$backendUrl/health" -Method GET | Select-Object -ExpandProperty Headers
```

### Test Production Flutter App

1. Build production APK:
   ```bash
   flutter build apk --release --dart-define=API_URL=https://your-backend.onrender.com
   ```

2. Install on device:
   - Transfer APK to device
   - Install and open
   - Test all upload flows

3. Monitor backend logs:
   - Check Render/Railway dashboard
   - Watch for errors
   - Verify security events

---

## 🎉 Success Criteria

**Your system is working correctly if:**

✅ Backend starts without errors  
✅ Health endpoint responds with 200 OK  
✅ Security headers are present  
✅ Rate limiting works  
✅ Authentication is required  
✅ File uploads succeed  
✅ Invalid files are rejected  
✅ Security events are logged  
✅ Flutter app connects to backend  
✅ Google Sign-In works  
✅ Images upload and display  
✅ Errors are handled gracefully  

**If all checks pass: Your app is production-ready!** 🚀

---

## 📝 Next Steps

1. **Test locally** (follow this guide)
2. **Fix any issues** found
3. **Rotate credentials** (see deployment_checklist.md)
4. **Deploy backend** to Render/Railway
5. **Test production** backend
6. **Build Flutter app** with production URL
7. **Deploy to Play Store**
8. **Monitor logs** for issues

---

**Need help?** Check the backend logs in `backend/logs/` for detailed error information.
