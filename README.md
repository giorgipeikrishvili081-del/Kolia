<p align="center">
  <img src="assets/icon/app_icon.png" width="160" alt="Kolia Logo">
</p>

# Kolia: Precision Field Research & Documentation

[English](#english) | [ქართული](#georgian)

---

<a name="english"></a>

## 🌍 Overview (English)

Kolia was born out of a simple observation: field research is messy, remote, and often completely disconnected from the digital world. I built this app to be the bridge between a muddy site and a professional report.

Most research tools are either too generic or too fragile for the field. Kolia is a robust, Material 3-powered Android application I designed to handle the heavy lifting of **BTK forms**, vegetation analysis, and soil classification while ensuring that "no signal" never means "data loss."

---

## 🚀 Key Abilities

### The Offline-First Engine
The heart of Kolia is its resilience. I've built it so researchers can record complex observations, classify soil, and pin locations to a map without any cellular connection. Everything is secured in a local **SQLite** vault and automatically synchronized to **Firebase** the moment you're back in range.

### Intelligent Document Automation
I believe in eliminating the "data entry tax." Kolia doesn't just store data; it translates it. With integrated **Google Drive & Docs APIs**, I've enabled the app to transform raw field observations into formatted, professional documents in shared folders with a single tap.

### Botanical Intelligence
Integrated with the **Pl@ntNet API**, the app acts as a research assistant. Snap a photo of a specimen, and I've implemented instant identification suggestions to speed up vegetation mapping and ecological surveys.

---

## 🏗 Project Architecture

I've structured the codebase to separate concerns, making it easier to maintain and scale:

```text
lib/
├── main.dart               # Entry point & global state initialization
├── models/                 # Data structures (TeamInfo, Form models)
├── screens/                # UI Layer (Material 3)
│   ├── btk_form_page.dart  # Dynamic BTK form logic
│   ├── plant_id_page.dart  # Pl@ntNet identification interface
│   ├── map_picker_page.dart# GIS & Location services
│   └── ...
├── services/               # The "Technical Engine"
│   ├── database_helper.dart# Local SQLite persistence
│   ├── sync_service.dart   # Background Workmanager sync
│   ├── google_drive_service.dart # Google Docs generation
│   ├── shorebird_service.dart    # OTA (Over-the-air) updates
│   └── ...
└── widgets/                # Shared UI components
    └── drawing_canvas.dart # Custom field sketch tool
```

---

## 📥 Downloads & Deployment

### Get the Latest Build
You can download the latest stable version of the app directly from the GitHub Releases page:

**[Download Kolia APK](https://github.com/giorgipeikrishvili081-del/Kolia/releases/latest)**

---

<a name="georgian"></a>

## 🇬🇪 ქართული ვერსია (Georgian)

### მიმოხილვა
კოლია შეიქმნა მარტივი დაკვირვების საფუძველზე: საველე კვლევა რთული და ხშირად ციფრული სამყაროსგან მოწყვეტილი პროცესია. მე შევქმენი ეს აპლიკაცია, რათა ის ყოფილიყო ხიდი საველე სამუშაოებსა და პროფესიონალურ ანგარიშებს შორის.

ყველაზე მეტი კვლევითი ინსტრუმენტი ან ძალიან ზოგადია, ან ძალიან სუსტი საველე პირობებისთვის. კოლია არის მყარი, Material 3-ზე დაფუძნებული Android აპლიკაცია, რომელიც შევქმენი **ბტკ ფორმების**, მცენარეულობის ანალიზისა და ნიადაგის კლასიფიკაციისთვის.

### ძირითადი შესაძლებლობები
*   **Offline-First ძრავი**: ჩანაწერების გაკეთება შესაძლებელია ინტერნეტის გარეშეც. მონაცემები ინახება ლოკალურ **SQLite** ბაზაში და ავტომატურად სინქრონიზდება **Firebase**-თან ინტერნეტის გაჩენისთანავე.
*   **დოკუმენტაციის ავტომატიზაცია**: **Google Drive & Docs API**-ების მეშვეობით, საველე მონაცემები ავტომატურად იქცევა პროფესიონალურ დოკუმენტებად.
*   **ბოტანიკური ინტელექტი**: **Pl@ntNet API** საშუალებას გაძლევთ მოახდინოთ მცენარეების იდენტიფიკაცია მხოლოდ ფოტოს გადაღებით.

---

## 🏗 პროექტის არქიტექტურა

კოდის სტრუქტურა დაყოფილია მოდულებად, რაც აადვილებს მის მართვას:

- **`lib/services/`**: აპლიკაციის "ტვინი". აქ ხდება მონაცემთა სინქრონიზაცია, ბაზებთან მუშაობა და გარე API-ებთან კავშირი.
- **`lib/screens/`**: ვიზუალური ნაწილი (Material 3). მოიცავს ფორმებს, რუკებს და პარამეტრებს.
- **`lib/widgets/`**: განმეორებადი კომპონენტები, მათ შორის ჩანახატების დასახატი ტილო.

---

## 🔐 License & Legal

This project is currently **Proprietary**. All rights are reserved by the developer.

---
*Built with ❤️ for researchers who get their boots dirty.*
