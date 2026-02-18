# Google Sign-In Setup Guide

## What has been configured:

### 1. **Backend Setup** ✅
- Firebase Authentication with Google Sign-In enabled
- google_sign_in package added to pubspec.yaml
- AuthService has proper Google Sign-In implementation

### 2. **Android Setup** ✅
- google-services.json configured with Firebase project ID
- AndroidManifest.xml has INTERNET permission
- OAuth client configured in google-services.json

### 3. **iOS Setup** ✅
- Info.plist has GIDClientID and URL schemes configured
- iOS can handle Google Sign-In callbacks

### 4. **Web Setup** ⚠️ **NEEDS CONFIGURATION**
- web/index.html has the meta tag with Client ID
- GoogleSignIn service initialized for web platform

### 5. **Flutter Code** ✅
- Welcome screen has functional Google Sign-In button
- Proper error handling and loading states
- Navigation to HomeScreen after successful login

## CRITICAL: Enable Google Provider in Firebase Authentication

### ❌ Current Error
`operation-not-allowed - The identity provider configuration is not found`

This means Google Sign-In is NOT enabled in Firebase.

### ✅ Fix: Enable Google in Firebase

**Follow these steps EXACTLY:**

1. Go to **[Firebase Console](https://console.firebase.google.com/)**
2. Click your project: **testpro-73a93**
3. In left menu: **Build** → **Authentication**
4. Click the **"Sign-in method"** tab at the top
5. A modal dialog will appear showing providers
6. Click **Google** in the "Additional providers" section
7. A config page will open - toggle the switch to **ON**
8. Select **Project support email** from the dropdown
9. Click **SAVE**

**You should see:**
- Google provider listed with an **ON/ENABLED** badge
- Green checkmark indicating it's active

### If Google is already enabled:

1. Double-check the toggle is truly **ON** (blue)
2. Verify the "Project support email" is set
3. Try clicking **SAVE** again
4. Then run your app: `flutter run -d chrome --web-port 5000`

### If you're still getting the error:

1. Go to **Project Settings** (gear icon at top)
2. Click **Service Accounts** tab
3. Click **Generate New Private Key**
4. This ensures Firebase has the right permissions
5. Then enable Google Sign-In again and save

After enabling, refresh your app and try again!

## Web OAuth Client Configuration

Once Google Sign-In is enabled in Firebase, you also need to configure the Web OAuth Client:

### Step 1: Go to Google Cloud Console
1. Visit [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: **testpro-73a93**
3. In the left menu, go to **APIs & Services** → **Credentials**

### Step 2: Create/Configure Web OAuth Client
1. Look for an existing OAuth 2.0 Client ID (Web Application type)
   - If it exists, click on it to edit
   - If not, click **Create Credentials** → **OAuth Client ID**
   - Select **Web Application**
   - Give it a name like "Flutter Web App"

### Step 3: Add Authorized Origins AND Authorized Redirect URIs
1. **Add Authorized JavaScript Origins**:
   - `http://localhost`
   - `http://localhost:5000`
   - `http://localhost:8000`
   - `http://127.0.0.1`
   - `http://127.0.0.1:5000`
   - Your production domain (if you have one)

2. **Add Authorized Redirect URIs** (IMPORTANT for localhost):
   - `http://localhost:5000/`
   - `http://localhost:8000/`
   - `http://127.0.0.1:5000/`
   - `http://127.0.0.1:8000/`
   - Your production domain callback URL

⚠️ **IMPORTANT**: Make sure both "Authorized Origins" AND "Authorized Redirect URIs" are configured!

### Step 4: Get Your Web Client ID
1. Copy the **Client ID** from the credentials
2. It should look like: `XXXXXX-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.apps.googleusercontent.com`
3. Update it in these files:
   - `web/index.html` - Replace in the meta tag
   - `lib/services/auth_service.dart` - Replace in the GoogleSignIn initialization

### Step 5: Update Your Flutter Code

Update `lib/services/auth_service.dart`:
```dart
static void _initializeGoogleSignIn() {
  if (kIsWeb) {
    _googleSignIn = GoogleSignIn(
      clientId: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
    );
  } else {
    _googleSignIn = GoogleSignIn();
  }
}
```

Update `web/index.html`:
```html
<meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
```

## Remaining Setup Steps (If Still Having Issues):

### For Android:
1. Get your app's SHA-1 fingerprint:
   ```
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```

2. Go to [Firebase Console](https://console.firebase.google.com/)
3. Select your project (testpro-73a93)
4. Go to Settings → Project Settings
5. Under "Your apps", select Android app
6. Add the SHA-1 fingerprint you got above
7. Download the updated google-services.json and replace the file

### For iOS:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. In Google Cloud Console, go to APIs & Services → Credentials
3. Create/find the iOS OAuth 2.0 Client ID
4. Update the bundle identifier if needed

## Testing:

1. Run the app: `flutter run -d chrome` (for web testing)
2. Tap "Continue with Google"
3. Select a Google account
4. You should be logged in and see the HomeScreen
5. Use the logout button (top right) to sign out

## About Web Deprecation Warnings:

The `google_sign_in` package shows deprecation warnings on web about using `signIn()` instead of `renderButton()`. This is normal and the functionality works fine. Future versions may switch to the newer `google_identity_services` package with native Google buttons, but for now the current implementation is stable and functional.

When users close the Google Sign-In popup, you'll see a "popup_closed" error in the console - this is expected and is handled gracefully without affecting the app.

## Troubleshooting:

- **"OAuth client was not found"**: The Web Client ID is not configured in Google Cloud Console. Follow Step 1-5 above.
- **"invalid_client"**: Same as above - the Client ID doesn't match or isn't registered.
- If you get "Sign in configuration error": The SHA-1 fingerprint doesn't match (for Android)
- If Google Sign-In dialog doesn't appear: Check internet permissions
- If you get Firebase exceptions: Ensure google-services.json is properly configured
