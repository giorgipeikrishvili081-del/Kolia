<p align="center">
  <img src="assets/icon/app_icon.png" width="160" alt="Kolia Logo">
</p>

# Kolia: Precision Field Research & Documentation

Kolia was born out of a simple observation: field research is messy, remote, and often completely disconnected from the digital world. We built this app to be the bridge between a muddy site and a professional report.

Most research tools are either too generic or too fragile for the field. Kolia is a robust, Material 3-powered Android application designed to handle the heavy lifting of **BTK forms**, vegetation analysis, and soil classification while ensuring that "no signal" never means "data loss."

---

## Key Abilities

### The Offline-First Engine
The heart of Kolia is its resilience. Researchers can record complex observations, classify soil, and pin locations to a map without any cellular connection. Everything is secured in a local **SQLite** vault and automatically synchronized to **Firebase** the moment you're back in range.

### Intelligent Document Automation
We believe in eliminating the "data entry tax." Kolia doesn't just store data; it translates it. With integrated **Google Drive & Docs APIs**, the app transforms raw field observations into formatted, professional documents in your team's shared folders with a single tap.

### Botanical Intelligence
Integrated with the **Pl@ntNet API**, the app acts as a research assistant. Snap a photo of a specimen, and get instant identification suggestions to speed up your vegetation mapping and ecological surveys.

---

## The Technical Engine

The codebase is organized to ensure the app remains snappy and reliable even in extreme field conditions.

- **`lib/services/`**: The brain of the application. 
    - **Sync & Persistence**: Uses a custom **SQLite** helper for local persistence and **Workmanager** for robust background synchronization to Firebase every 15 minutes (or whenever connectivity returns).
    - **Cloud Automation**: The `GoogleDriveService` generates clean HTML reports directly from field data and uses the **Google Drive API** to convert them into editable Google Docs.
    - **Live Updates**: Integrated with **Shorebird**, allowing us to push critical bug fixes and form updates to researchers in the field without requiring a manual APK reinstall.
- **`lib/screens/`**: A clean, Material 3 implementation. We use reactive state management (`ValueListenable`) to keep the interface fast and responsive.
- **`lib/widgets/`**: Reusable components, including a custom **Drawing Canvas** for field sketches and structural diagrams.

*Note: For security, all private API keys (Pl@ntNet, Google Cloud) and `google-services.json` are excluded from version control via `.gitignore`.*

---

##  Downloads & Deployment

### Get the Latest Build
You can download the latest stable version of the app directly from our GitHub Releases page:

**[Download Kolia APK](https://github.com/giorgipeikrishvili081-del/Kolia/releases/tag/1.7.0)**

### Installation
1. Download the `.apk` file to your Android device.
2. Enable "Install from Unknown Sources" in your Android settings if prompted.
3. Open the file to complete the installation.

---

## Developer Setup

If you want to build Kolia from source:

1. **Clone the Repo**:
   ```bash
   git clone https://github.com/giorgipeikrishvili081-del/Kolia.git
   ```
2. **Install Flutter**: Ensure you are using the latest stable channel.
3. **Dependencies**: Run `flutter pub get`.
4. **Configuration**: You will need to provide your own `google-services.json` in `android/app/`.
5. **Run**: `flutter run`.

---

## Permissions & Roles

Kolia uses a role-based access system to keep data organized:
- **Field Teams**: Can create, edit, and sync their own reports. Data is isolated by team identity to ensure privacy and focus.
- **Admins**: Access to global statistics and bulk export features for project oversight.

---

## License & Legal

This project is currently **Proprietary**. All rights are reserved by the development team. 

For inquiries regarding commercial use, custom deployments, or API access, please contact the repository owner.

---
*Built with ❤️ for researchers who get their boots dirty.*
