# Native platform permissions

After generating Android/iOS folders with `flutter create --platforms=android,ios .`:

## iOS

Add the following to `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save approved Panchayat post graphics to your photo library.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select Panchayat photos and save completed post graphics.</string>
<key>NSCameraUsageDescription</key>
<string>Capture before and after photos of Panchayat development work.</string>
```

## Android

Confirm the Android app has an appropriate minimum SDK for `image_picker`, `gal`, Firebase Auth and `share_plus`. Android 10+ saves through MediaStore; older supported Android versions may require storage permission according to the `gal` package's current setup guide.

## Phone authentication

Register SHA-1/SHA-256 signing fingerprints in Firebase, enable Phone provider, and configure SMS region policy. For iOS, configure APNs and URL schemes as required by Firebase Phone Auth.
