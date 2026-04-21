# SafeWalk Pro 🇨🇲
**Intelligent Pedestrian Safety & Emergency Response System**

SafeWalk Pro is a professional-grade Flutter application designed to enhance personal safety for pedestrians, specifically tailored for the Cameroonian context. It combines real-time sensor analysis to detect "distracted walking" with a robust, multi-channel SOS system and a fail-safe Journey Timer.

## 🚀 Key Features

### 1. Intelligent Distraction Detection
The app uses the device's accelerometer to detect dangerous walking habits.
*   **The Logic:** It monitors for a specific "unsafe usage" signature: Movement Magnitude > 2.5 (walking) + Y-Axis Tilt between 3.0 and 9.0 (looking at the phone).
*   **The Response:** Triggers a high-pitched panic siren and haptic feedback to alert the user to look up and stay aware of their surroundings.

### 2. Centralized SOS Hub
A large, accessible SOS button designed for high-stress situations.
*   **Manual Trigger:** Allows users to choose between **SMS (Broadcast to all)** or **WhatsApp (Contact Picker)**.
*   **Regional Accuracy:** Automatically formats 9-digit Cameroonian numbers to the international `+237` standard to ensure message delivery.
*   **Live GPS Integration:** Every alert includes a precise Google Maps link of the user's current location.

### 3. Safety Journey Timer
A fail-safe feature for users walking home or through unfamiliar areas.
*   **Adjustable Scale:** Slider-based control from 10 seconds to 1 hour.
*   **Automatic Trigger:** If the timer reaches zero and the user hasn't checked in, the app **automatically** initiates a broadcast SMS SOS to all 5 trusted contacts without requiring further user interaction.

### 4. Panic Siren & Toolbox
*   **Digital Siren:** A loud, looping alert to draw attention or deter threats.
*   **I Am Safe:** A "Check-in" feature that sends a quick SMS to loved ones letting them know the user has arrived safely.

## 🛠 Tech Stack
*   **Framework:** Flutter (Targeting 3.27+ standards)
*   **Language:** Dart & Kotlin (2.1.0)
*   **Sensors:** `sensors_plus` for real-time motion analysis.
*   **Location:** `geolocator` for high-accuracy GPS coordinates.
*   **Audio:** `audioplayers` for emergency sirens.
*   **Persistence:** `shared_preferences` for contact storage.
*   **Build Tools:** AGP 8.9.1, Gradle 8.11.1.

## 📱 Regional Support (Cameroon)
*   Supports all 9-digit local numbers (MTN, Orange, Nexttel, Camtel).
*   Optimized for devices common in the local market (e.g., TECNO, Infinix).
*   Designed to work efficiently under varying network conditions (SMS fallback for zero-data scenarios).

## 📥 Installation

1.  **Clone the repository:**
    ```sh
    git clone https://github.com/your-username/safewalk-pro.git
    ```
2.  **Install dependencies:**
    ```sh
    flutter pub get
    ```
3.  **Add Assets:** Ensure an `alert.mp3` file is placed in the `assets/` folder and registered in `pubspec.yaml`.
4.  **Run the app:**
    ```sh
    flutter run
    ```

## ⚠️ Disclaimer
SafeWalk Pro is a safety assistant and should not replace professional emergency services. Effectiveness depends on device sensor accuracy, GPS availability, and cellular network status.

---
**Developed for the safety of every Cameroonian pedestrian.** 🇨🇲
