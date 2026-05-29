# Frontend Desktop Setup (Flutter)

## 1. Kiểm tra Flutter

Đảm bảo Flutter đã được cài đặt:

```powershell
flutter doctor
```

Nếu thiếu Visual Studio Build Tools, cài:

* Visual Studio Community
* Workload: **Desktop development with C++**

---

## 2. Di chuyển tới thư mục frontend

```powershell
cd frontend
```

Kiểm tra project Flutter:

```powershell
dir
```

Đảm bảo có file:

```text
pubspec.yaml
```

---

## 3. Enable Windows Desktop

Chỉ cần thực hiện một lần:

```powershell
flutter config --enable-windows-desktop
```

---

## 4. Cài dependencies

```powershell
flutter pub get
```

---

## 5. Chạy ứng dụng desktop

```powershell
flutter run -d windows
```

Flutter sẽ build và mở ứng dụng desktop trên Windows.

---

## 6. Chạy Backend API

Mở terminal khác và chạy backend:

```powershell
uvicorn app:app --host 0.0.0.0 --port 8000 --reload
```

Frontend sẽ gọi API tại:

```text
http://localhost:8000
```

---

## 7. Build file `.exe`

Build bản release:

```powershell
flutter build windows
```

File executable nằm tại:

```text
build/windows/x64/runner/Release/
```

---

# Common Issues

## Không nhận Windows Desktop

Kiểm tra devices:

```powershell
flutter devices
```

Nếu chưa có Windows Desktop:

```powershell
flutter config --enable-windows-desktop
```

---

## Thiếu Visual Studio

Nếu gặp lỗi:

```text
Building Windows application requires Visual Studio
```

Cài:

* Visual Studio Community
* Desktop development with C++

---

## Thiếu dung lượng ổ C

Dọn cache Flutter:

```powershell
flutter clean
```

Hoặc mở Disk Cleanup:

```powershell
cleanmgr
```
