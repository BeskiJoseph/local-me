# TestPro - Location-Based Social Platform

A Flutter-based social media application with location-aware content delivery, built with Firebase and Cloudflare R2 for media storage.

## Features

- 🔐 **Authentication**: Email/password and Google Sign-In
- 📍 **Location-Based Content**: Posts organized by local, national, and global feeds
- 📸 **Media Upload**: Secure image and video uploads via Cloudflare R2
- 👥 **Social Features**: Follow users, like and comment on posts
- 🌐 **Multi-Platform**: Android, iOS, Web, Linux, macOS, Windows support

---

## Prerequisites

- **Flutter SDK**: ^3.10.3
- **Node.js**: >=20.0.0 (for backend)
- **Firebase Project**: With Authentication, Firestore, and Cloud Functions enabled
- **Cloudflare R2**: For media storage

---

## Project Structure

```
testpro-main/
├── lib/                    # Flutter application code
│   ├── models/            # Data models
│   ├── screens/           # UI screens
│   ├── services/          # Business logic & API calls
│   ├── widgets/           # Reusable UI components
│   └── utils/             # Helper functions
├── backend/               # Node.js backend for media uploads
├── functions/             # Firebase Cloud Functions
└── assets/                # Static assets

backend/
├── server.js              # Express server
├── .env.example           # Environment template
└── package.json           # Dependencies
```

---

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/BeskiJoseph/WorkerHTTPSTESTPRO.git
cd testpro-main
```

### 2. Flutter App Setup

#### Install Dependencies

```bash
flutter pub get
```

#### Configure Firebase

1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Enable **Authentication** (Email/Password and Google)
3. Enable **Cloud Firestore**
4. Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
5. Place them in the appropriate directories:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

#### Configure Environment Variables

For production builds, set environment variables:

```bash
# API Backend URL
flutter run --dart-define=API_URL=https://your-backend.com

# Google OAuth Client ID (Web only)
flutter run --dart-define=GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
```

### 3. Backend Setup

#### Navigate to Backend Directory

```bash
cd backend
```

#### Install Dependencies

```bash
npm install
```

#### Configure Environment

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your credentials:

```env
# Server Configuration
PORT=4000
NODE_ENV=development

# Firebase Admin SDK
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com

# Cloudflare R2
R2_ACCOUNT_ID=your-account-id
R2_ACCESS_KEY_ID=your-access-key
R2_SECRET_ACCESS_KEY=your-secret-key
R2_BUCKET_NAME=your-bucket-name
R2_PUBLIC_BASE_URL=https://your-r2-domain.com

# CORS (comma-separated for production)
CORS_ORIGIN=*
```

#### Get Firebase Admin Credentials

1. Go to Firebase Console > Project Settings > Service Accounts
2. Click "Generate new private key"
3. Copy values to `.env` file

#### Get Cloudflare R2 Credentials

1. Go to Cloudflare Dashboard > R2
2. Create a bucket
3. Click "Manage R2 API Tokens"
4. Create a token with Read & Write permissions
5. Copy credentials to `.env` file

#### Run Backend

```bash
# Development
npm run dev

# Production
npm start
```

### 4. Firebase Cloud Functions Setup

#### Navigate to Functions Directory

```bash
cd functions
```

#### Install Dependencies

```bash
npm install
```

#### Deploy Functions

```bash
firebase deploy --only functions
```

### 5. Deploy Firestore Security Rules

```bash
firebase deploy --only firestore:rules
```

---

## Running the Application

### Development

```bash
# Run on connected device/emulator
flutter run

# Run on web
flutter run -d chrome

# Run with custom API URL
flutter run --dart-define=API_URL=http://localhost:4000
```

### Production Build

```bash
# Android
flutter build apk --release --dart-define=API_URL=https://your-backend.com

# iOS
flutter build ios --release --dart-define=API_URL=https://your-backend.com

# Web
flutter build web --release --dart-define=API_URL=https://your-backend.com
```

---

## Environment Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `API_URL` | Backend API URL | `https://api.example.com` |
| `GOOGLE_CLIENT_ID` | Google OAuth Client ID (Web) | `123-abc.apps.googleusercontent.com` |

### Setting Environment Variables

**Development:**
```bash
flutter run --dart-define=API_URL=http://localhost:4000
```

**CI/CD (GitHub Actions example):**
```yaml
- name: Build Flutter App
  run: flutter build apk --release --dart-define=API_URL=${{ secrets.API_URL }}
```

---

## Troubleshooting

### Common Issues

**1. "API_URL not set" warning**
- Set `API_URL` via `--dart-define` flag
- Default URL is used if not set (check console logs)

**2. Images not loading**
- Verify backend is running
- Check R2 credentials in backend `.env`
- Verify `R2_PUBLIC_BASE_URL` is correct

**3. Google Sign-In fails on web**
- Set `GOOGLE_CLIENT_ID` environment variable
- Verify client ID matches Firebase Console

**4. Build errors after setup**
```bash
flutter clean
flutter pub get
flutter run
```

**5. Backend upload fails**
- Check Firebase token is valid
- Verify R2 credentials
- Check backend logs for errors

---

## Security Best Practices

⚠️ **NEVER commit the following files:**
- `backend/.env`
- `**/serviceAccountKey.json`
- Any file containing API keys or secrets

✅ **Always:**
- Use environment variables for secrets
- Rotate credentials if accidentally exposed
- Use HTTPS in production
- Enable Firestore security rules

---

## Deployment

### Backend Deployment (Render/Railway)

1. Create new web service
2. Connect your repository
3. Set environment variables from `.env.example`
4. Deploy

### Flutter Web Deployment

```bash
flutter build web --release --dart-define=API_URL=https://your-backend.com
# Upload build/web/ to hosting provider (Firebase Hosting, Netlify, etc.)
```

### Mobile App Deployment

- **Android**: Upload APK/AAB to Google Play Console
- **iOS**: Upload to App Store Connect via Xcode

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

This project is licensed under the ISC License.

---

## Support

For issues and questions:
- Create an issue on GitHub
- Check existing documentation
- Review Firebase and Flutter documentation

---

## Acknowledgments

- Firebase for backend services
- Cloudflare R2 for media storage
- Flutter team for the framework 