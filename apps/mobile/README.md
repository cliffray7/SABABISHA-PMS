# Sababisha PMS mobile

Flutter client for the existing PMS API. It currently implements registration,
login, email OTP verification, secure token persistence, refresh-token retry,
account restoration, and logout.

## Run

Install Flutter, then from this directory run:

```powershell
flutter pub get
flutter create . --platforms=android,ios
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5141/api/v1
```

`10.0.2.2` addresses the host machine from an Android emulator. For a physical
device use the LAN address of the API host, for example
`http://192.168.1.20:5141/api/v1`. The API must permit that client origin where
the platform enforces CORS (Flutter mobile itself does not).

Run checks with `flutter analyze` and `flutter test`.
