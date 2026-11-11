<p align="center">
  <img src="docs/images/app-icon.png" width="132" alt="3105 app icon">
</p>

<h1 align="center">3105 (v2.0 — Official iOS 27+ · LocalDevVPN & Pairing · Arabic RTL)</h1>

<p align="center">
  An iOS content hub and manager for patches, app data, dialer themes, and PosterBoard wallpapers — now supporting all official iOS 27+ releases and universal iOS versions via <strong>3105 Device Pairing</strong> &amp; <strong>LocalDevVPN (10.7.1.1 / 10.7.0.1)</strong>, with full <strong>Arabic (العربية) &amp; RTL</strong> layout support.
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-2.0-E6753A?style=flat-square">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-16.0–18.7.x%20%7C%2026.0–26.x%20%7C%2027.0%2B%20Official%20%26%20Beta-222222?style=flat-square">
  <img alt="LocalDevVPN" src="https://img.shields.io/badge/LocalDevVPN-10.7.1.1%2F32%20%C2%B7%2010.7.0.1%2F32-2EA043?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Languages" src="https://img.shields.io/badge/languages-العربية%20(RTL)%20%7C%20English%20%7C%20Tiếng%20Việt%20%7C%20简体中文-E6753A?style=flat-square">
</p>

## What's New in This Build

- **Official iOS 27.0+ & Universal iPhone Support (`SupportPolicy.swift` & `PackageCompatibilityEvaluator`)** — Removes the beta-only restriction on iOS 27 and enables full support across all official iOS 27.0, 27.1, 27.2+ releases and any iPhone iOS version (`16.0+`) via **Device Pairing (`3105`)** and **LocalDevVPN**.
- **Built-in LocalDevVPN & Device Pairing Hub (`LocalVPNPairingService.swift` & `PairingVPNView.swift`)**:
  - **LocalDevVPN Tunnel Control & Live Interface Monitor**: Connects and monitors the local tunnel (`Tunnel IP: 10.7.1.1/32`, `Device IP: 10.7.0.1/32`) via `NETunnelProviderManager` and POSIX `getifaddrs` (`utun*`).
  - **Developer Mode & Paired Devices (`3105`)**: Implements Apple's `lockdownd` wire protocol over `10.7.0.1:62078` with background Heartbeat keep-alive, `.mobiledevicepairing` / `.plist` import & generation under the `3105` paired device identity, and `house_arrest` / container staging fallback in `ContainerStore`.
- **Full Arabic Localization (`ar.lproj/Localizable.strings`) & Automatic RTL Layout**:
  - Complete Arabic translation (360+ strings) across all views, alerts, onboarding, marketplace, patches, cleaner, wallpapers, and settings.
  - Automatic Right-to-Left (`LayoutDirection.rightToLeft`) mirroring injected across the SwiftUI view hierarchy and directional chevrons (`chevron.forward` / `chevron.backward`).
