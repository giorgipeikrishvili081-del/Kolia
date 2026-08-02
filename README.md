# Kolia - Field Research & Landscape Management

An advanced Android application for ecological field research, vegetation analysis, and soil classification.

## Features
- **Landscape Forms**: Comprehensive digital forms for field observations.
- **Offline First**: Full SQLite integration for data collection without internet.
- **Map Integration**: Pinpoint research locations with precision.
- **Plant Identification**: Automated ID tool for researchers using Pl@ntNet API.
- **Cloud Sync**: Seamless Firebase synchronization for team collaboration.
- **Export**: Generate PDF/CSV reports directly from the app.
- **Dynamic UI**: Material 3 theme that adapts to team identity.

## Tech Stack
- **Framework**: Flutter (Dart)
- **Database**: SQLite (Local) & Firebase Firestore (Cloud)
- **State Management**: ValueNotifiers & Cached Team Identity
- **Maps**: Flutter Map / Leaflet
- **Auth**: Team-based authentication with local caching.

## Installation
1. **Clone the repo**: 
   ```bash
   git clone https://github.com/giorgipeikrishvili081-del/kolia-research-app.git
   ```
2. **Install dependencies**: 
   ```bash
   flutter pub get
   ```
3. **Configuration**:
   - Add your `google-services.json` to `android/app/`.
   - Add your `GoogleService-Info.plist` to `ios/Runner/`.
   - (Optional) Create a `lib/services/secrets.dart` to store API keys if you move them out of the source.

4. **Run**: 
   ```bash
   flutter run
   ```

## Permissions
- **Admin/Supervisor**: Full edit rights, statistics access, and "Delete All" capabilities.
- **Team**: Can create, edit, and manage their own local/cloud forms. Restricted to read-only for other teams.

## License
This project is proprietary. All rights reserved.
