# VirgoPay Flutter WebView Demo

This is a demo Flutter application that integrates the **VirgoPay Widget** using an in-app WebView.

## Tech Stack / Dependencies

### Flutter Dependencies

- [`webview_flutter`](https://pub.dev/packages/webview_flutter) – WebView rendering
- [`webview_flutter_android`](https://pub.dev/packages/webview_flutter_android) – Android-specific WebView extensions
- [`url_launcher`](https://pub.dev/packages/url_launcher) – External URL handling
- [`file_picker`](https://pub.dev/packages/file_picker) – Android file upload support
- [`cupertino_icons`](https://pub.dev/packages/cupertino_icons) – iOS-style icons

## Features

- Loads the VirgoPay Widget inside a WebView
- Supports opening external links via `url_launcher` (if needed)
- Provides a simple reference implementation for mobile integration

## Getting Started

### Install dependencies
```bash
flutter pub get
