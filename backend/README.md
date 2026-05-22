# PaperToObsidian Backend (AI OCR Service)

Backend API này đóng vai trò là lõi AI của ứng dụng PaperToObsidian. Hệ thống sử dụng model `nougat-ocr` (của Meta) được bọc qua framework FastAPI để chuyển đổi file PDF bài báo khoa học thành định dạng Markdown.

## Tính năng cốt lõi (Giai đoạn 1 & 2)
- Nhận file PDF qua endpoint `/convert` (`multipart/form-data`).
- Chạy mô hình AI bóc tách nội dung, giữ nguyên cấu trúc toán học (LaTeX) và bảng biểu.
- Tự động băm nhỏ Markdown (Parsing) thành các Node (Abstract, Introduction, Method...) để hỗ trợ team dọn sẵn cấu trúc JSON.
- Tự động lưu bản cứng file `.mmd` cực sạch vào thư mục `outputs/` với tên file là tên bài báo.
- **Auto-cleanup:** Tự động dọn rác (xóa cache ảnh/PDF tạm) sau mỗi lần request để tiết kiệm ổ cứng server.

---

## 🛠 Yêu cầu hệ thống
- Python 3.9 hoặc 3.10+
- Môi trường ảo (`venv`)
- Khuyến nghị chạy trên máy có GPU, hoặc CPU (sẽ mất thời gian xử lý lâu hơn).

---

## 🚀 Cài đặt & Khởi chạy (Local)

### Bước 1: Khởi tạo môi trường ảo
Di chuyển vào thư mục backend service và tạo môi trường ảo (Virtual Environment):

```powershell
cd backend\nougat-api-service

# Tạo môi trường ảo (Đợi 15s để hệ thống copy file)
python -m venv .venv

# Kích hoạt môi trường ảo
.\.venv\Scripts\Activate.ps1

Bước 2: Cài đặt thư viện (Đã fix lỗi xung đột)
ĐẶC BIỆT LƯU Ý: Phải cài đúng các phiên bản dưới đây để tránh lỗi sập server do các bản update mới nhất của thư viện pypdfium2 và transformers không tương thích với mã nguồn Nougat.

PowerShell
pip install fastapi uvicorn python-multipart nougat-ocr "pypdfium2<5" transformers==4.38.2 albumentations==1.3.1
Bước 3: Tải Model Nougat
Chạy lệnh sau để kéo Model AI về máy (chỉ cần làm 1 lần đầu tiên):

PowerShell
nougat --download
Bước 4: Thiết lập biến môi trường & Bật Server
Model vừa tải về sẽ nằm ở thư mục .cache trong User Profile của Windows. Hãy set đường dẫn và khởi chạy uvicorn:

PowerShell
# Set biến môi trường trỏ đến model
$env:NOUGAT_CHECKPOINT="$env:USERPROFILE\.cache\torch\hub\nougat-0.1.0-small"

# Chạy Server
uvicorn app:app --host 0.0.0.0 --port 8000 --reload
API sẽ có sẵn tại:

Health check: http://127.0.0.1:8000/health

Swagger UI (Docs): http://127.0.0.1:8000/docs

📖 Cấu trúc API Contract (Dành cho Dev 3 & Dev 4)
1. GET /health
Kiểm tra trạng thái server. Trả về HTTP 200 OK nếu hệ thống sẵn sàng.

2. POST /convert
Upload file PDF và nhận về cấu trúc bài báo phân mảnh.

Headers: - N/A (FastAPI đã mở CORS cho phép gọi từ mọi Origin).

Body (multipart/form-data):

file: File PDF cần chuyển đổi (Bắt buộc).

start: (Tùy chọn) Số trang bắt đầu cắt (Int).

stop: (Tùy chọn) Số trang kết thúc (Int).

Ví dụ gọi API bằng PowerShell:

PowerShell
Invoke-RestMethod `
    -Uri "[http://127.0.0.1:8000/convert](http://127.0.0.1:8000/convert)" `
    -Method Post `
    -Form @{ file = Get-Item "D:\papers\Attention_Is_All_You_Need.pdf" }
JSON Response trả về (Output mong đợi):

JSON
{
    "status": "success",
    "data": {
        "paper_title": "Attention Is All You Need",
        "nodes": {
            "Metadata_Frontmatter": "Ashish Vaswani, Google Brain...",
            "Abstract": "The dominant sequence transduction models are based on...",
            "Introduction": "Recurrent neural networks, long short-term memory...",
            "Conclusion": "In this work, we presented the Transformer..."
        },
        "raw_markdown": "# Attention Is All You Need\n\nAshish Vaswani..."
    }
}