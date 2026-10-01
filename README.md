# CCCD NFC Export Image (.deb cho iPhone Jailbreak)

Ứng dụng iOS dạng gói `.deb` dành cho iPhone Jailbreak (**Dopamine Rootless & RootHide**) giúp đọc chip NFC trên thẻ **Căn cước công dân (CCCD)** Việt Nam và xuất ảnh chân dung ra file `.jpg`.

---

## 🚀 Tính năng nổi bật
* **Quét mã vạch mặt sau thẻ (Vision OCR):** Tự động nhận diện 3 dòng MRZ ở mặt sau CCCD bằng camera (Số CCCD, Ngày sinh, Ngày hết hạn), không cần nhập tay.
* **Hỗ trợ mã CAN (6 số):** Có thể nhập nhanh 6 số CAN ở góc dưới mặt trước thẻ để xác thực.
* **Giao tiếp NFC ISO 7816 & ICAO 9303:**
  * Xác thực bảo mật BAC (Basic Access Control) với chip eMRTD.
  * Thiết lập kênh mã hóa Secure Messaging (3DES CBC + Retail MAC ISO 9797-1).
  * Đọc dữ liệu sinh trắc học khuôn mặt từ **Data Group 2 (DG2)**.
* **Trích xuất & Xuất ảnh JPG:**
  * Tự động giải mã định dạng ảnh JPEG / JPEG 2000 từ dữ liệu DG2.
  * Xuất ảnh ra `.jpg` độ phân giải gốc.
  * Lưu trực tiếp vào Thư viện Ảnh (Camera Roll) hoặc Chia sẻ qua AirDrop / Zalo / Files...
* **Tương thích 100% Objective-C (`.h` và `.m`):**
  * Không phụ thuộc vào Swift runtime dylib, nhẹ và cực kỳ ổn định trên các bản Jailbreak iOS 15.0 - 16.x+.
  * Hỗ trợ đầy đủ cả `THEOS_PACKAGE_SCHEME=roothide` và `THEOS_PACKAGE_SCHEME=rootless`.

---

## 📁 Cấu trúc dự án

```
export_image_nfc/
├── Makefile                          # Cấu hình biên dịch Theos (Rootless & RootHide)
├── control                           # Metadata gói Debian
├── ExportImageNFC.entitlements       # Quyền CoreNFC ISO7816 Tag
├── ExportImageNFC-Info.plist         # Info.plist cấu hình NFC AID & quyền
├── postinst                          # Script tự động cập nhật uicache khi cài deb
├── prerm                             # Script dọn dẹp uicache khi gỡ deb
├── commit-push.bat                   # Batch script đẩy lên GitHub để tự động build
├── .github/
│   └── workflows/
│       └── build.yml                 # CI/CD tự động build file .deb trên macOS-14
├── main.m                            # Entry point ứng dụng
├── AppDelegate.h / .m                # Quản lý vòng đời ứng dụng & Navigation
├── MainViewController.h / .m         # Giao diện chính (Xem ảnh, các nút chức năng)
├── MRZScannerViewController.h / .m   # Quét camera OCR mặt sau CCCD (Vision framework)
├── CCCDReaderManager.h / .m          # Quản lý đọc chip NFC qua CoreNFC
├── BACSession.h / .m                 # Quản lý mã hóa Secure Messaging ICAO 9303
├── CryptoUtils.h / .m                # Các hàm mật mã học 3DES, Retail MAC, SHA1, Check Digit
└── DG2Parser.h / .m                  # Giải mã ảnh khuôn mặt từ DG2 sang JPG
```

---

## 🛠️ Hướng dẫn Build file `.deb`

### Cách 1: Tự động qua GitHub Actions (Khuyên dùng)
1. Chạy file `commit-push.bat` trong thư mục này.
2. Nhập URL Git repository của bạn và message commit.
3. Script sẽ tự động đẩy code lên GitHub.
4. GitHub Actions sẽ tự động kích hoạt workflow (chạy trên máy ảo `macos-14`) và biên dịch ra:
   * Gói `.deb` cho **RootHide** (`THEOS_PACKAGE_SCHEME=roothide`)
   * Gói `.deb` cho **Dopamine Rootless** (`THEOS_PACKAGE_SCHEME=rootless`)
5. Vào tab **Actions** hoặc **Releases** trên GitHub để tải file `.deb` về cài đặt.

### Cách 2: Biên dịch thủ công bằng Theos (trên Mac hoặc trực tiếp trên iPhone qua NewTerm)
* **Build cho RootHide:**
  ```bash
  make clean
  make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
  ```
* **Build cho Dopamine Rootless:**
  ```bash
  make clean
  make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
  ```
* File `.deb` hoàn chỉnh sẽ nằm trong thư mục `packages/`.

---

## 📲 Hướng dẫn Cài đặt & Sử dụng trên iPhone

1. **Cài đặt:**
   * Dùng công cụ `tool_install_deb` (có sẵn trong thư mục `lap_trinh_ios`) hoặc chép file `.deb` vào iPhone và cài qua **Sileo / Zebra / Filza**.
   * Sau khi cài đặt, icon ứng dụng **CCCD NFC Export** sẽ xuất hiện trên màn hình chính.
2. **Sử dụng:**
   * **Bước 1:** Mở app, chọn **"Camera Mặt Sau"** và bấm **"📸 Mở Camera Quét Mặt Sau Thẻ"** để tự động nhận diện thông tin MRZ (hoặc chuyển sang tab **"Mã CAN"** để nhập 6 số ở mặt trước thẻ).
   * **Bước 2:** Bấm nút màu xanh **"📡 Bắt Đầu Quét NFC CCCD"**.
   * **Bước 3:** Áp sát vùng đỉnh lưng iPhone (ngay cạnh cụm camera sau) vào con chip tròn màu vàng ở mặt sau thẻ CCCD và giữ yên 2–3 giây.
   * **Bước 4:** Sau khi thông báo thành công, ảnh chân dung sẽ hiển thị trên màn hình. Bấm **"💾 Lưu Vào Album"** hoặc **"📤 Xuất File .JPG"** để lưu hoặc chia sẻ.
