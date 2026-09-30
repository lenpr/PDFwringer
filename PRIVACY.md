# Privacy Policy

PDFwringer processes all files locally on your device.

- **No data collection**: The app does not collect or transmit personal data, documents, or usage analytics.
- **No network requests**: The app makes no outbound network connections of any kind.
- **No third-party SDKs**: The app contains no third-party frameworks, analytics libraries, or telemetry code.
- **Local file access only**: Files are accessed only when explicitly selected by you through the system file picker, drag-and-drop, or the Open Recent menu. The app operates within the macOS sandbox with user-selected file access only.
- **Recent documents**: To make Open Recent work after relaunch, the app stores up to ten security-scoped file bookmarks in its sandboxed preferences. It does not store a separate plaintext path list. Choosing File > Open Recent > Clear Menu deletes these bookmarks and the system recent-document list.
- **Temporary files**: The app stages replacement files on the selected destination volume during processing. Compression keeps one prepared copy there while you compare the original and result; Save Result publishes that exact copy. Cancel, changing settings, leaving the workflow, or normal shutdown discards an unsaved prepared copy. An interrupted process or system crash can leave a temporary replacement file on disk. These copies are never uploaded.
- **Diagnostics and crash logs**: Operational diagnostics use Apple Unified Logging. macOS can generate system crash reports, governed by your system diagnostic and sharing settings. PDFwringer does not upload reports or install a custom crash handler. Use Help > Open Console to inspect system reports and logs. Older versions may have left a `crash.log` in the app's sandboxed `Library/Logs/PDFwringer` folder; this version does not append to or upload that file.
