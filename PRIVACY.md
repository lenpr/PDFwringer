# Privacy Policy

PDFwringer processes all files locally on your device.

- **No data collection**: The app does not collect or transmit personal data, documents, or usage analytics.
- **No network requests**: The app makes no outbound network connections of any kind.
- **No third-party SDKs**: The app contains no third-party frameworks, analytics libraries, or telemetry code.
- **Local file access only**: Files are accessed only when explicitly selected by you through the system file picker, drag-and-drop, or the Open Recent menu. The app operates within the macOS sandbox with user-selected file access only.
- **Recent documents**: To make Open Recent work after relaunch, the app stores up to ten security-scoped file bookmarks in its sandboxed preferences. It does not store a separate plaintext path list. Choosing File > Open Recent > Clear Menu deletes these bookmarks and the system recent-document list.
- **Temporary files**: The app creates temporary replacement files during processing (e.g., compression, splitting, color adjustment). They are staged on the selected destination volume and cleaned up automatically.
- **Diagnostics and crash logs**: Operational diagnostics use Apple Unified Logging. macOS can generate system crash reports, governed by your system diagnostic and sharing settings. PDFwringer does not upload reports or install a custom crash handler. Use Help > Open Console to inspect system reports and logs. Older versions may have left a `crash.log` in the app's sandboxed `Library/Logs/PDFwringer` folder; this version does not append to or upload that file.
