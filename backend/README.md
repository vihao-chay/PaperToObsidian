# PaperToObsidian Backend

Backend này dùng `nougat-ocr` để chuyển PDF bài báo khoa học sang Markdown/MMD, trích metadata cơ bản, rồi có thể lưu thành note `.md` trực tiếp vào Obsidian vault.

## Tính năng hiện có

- `GET /health`: kiểm tra trạng thái API, model Nougat và cấu hình Obsidian.
- `POST /convert`: nhận file PDF, chạy Nougat OCR, trả Markdown + nodes + metadata.
- Lưu bản `.mmd` vào thư mục `outputs/`.
- Nếu cấu hình `OBSIDIAN_VAULT_PATH`, tự tạo note Markdown trong Obsidian.
- Validate PDF, giới hạn dung lượng upload, kiểm tra page range `start/stop`.
- Tạo note có YAML frontmatter để Obsidian đọc tốt hơn.

## Cài đặt local

```powershell
cd backend\nougat-api-service
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Nếu dùng GPU trên Windows, hãy cài PyTorch đúng bản CUDA trước khi cài/runs Nougat.

## Tải model Nougat

```powershell
nougat --download
```

Sau khi tải, set checkpoint. Ví dụ với model small:

```powershell
$env:NOUGAT_CHECKPOINT="$env:USERPROFILE\.cache\torch\hub\nougat-0.1.0-small"
```

## Cấu hình Obsidian

Obsidian vault là một thư mục chứa các file Markdown. Để backend lưu note vào vault, set:

```powershell
copy .env.example .env
```

Sau đó sửa file `.env`:

```powershell
OBSIDIAN_VAULT_PATH=D:\Obsidian\MyVault
```

Tuỳ chọn thư mục con để lưu paper notes và bật tách section thành node riêng:

```powershell
OBSIDIAN_PAPERS_DIR=Papers
OBSIDIAN_SPLIT_NODES=true
```

Nếu không set `OBSIDIAN_VAULT_PATH`, API vẫn chạy OCR và lưu `.mmd` trong `outputs/`, nhưng response sẽ báo `obsidian.saved = false`.

## Chạy server

```powershell
uvicorn app:app --host 0.0.0.0 --port 8000 --reload
```

Backend sẽ tự đọc file `.env` trong thư mục `backend\nougat-api-service`. Nếu bạn set biến bằng PowerShell trực tiếp, biến đó sẽ được ưu tiên hơn giá trị trong `.env`.

URL hữu ích:

- Health check: `http://127.0.0.1:8000/health`
- Swagger UI: `http://127.0.0.1:8000/docs`

## Gọi API

Upload toàn bộ PDF:

```powershell
Invoke-RestMethod `
  -Uri "http://127.0.0.1:8000/convert" `
  -Method Post `
  -Form @{ file = Get-Item "D:\papers\Attention_Is_All_You_Need.pdf" }
```

Chỉ xử lý trang 1 đến 5:

```powershell
Invoke-RestMethod `
  -Uri "http://127.0.0.1:8000/convert?start=1&stop=5" `
  -Method Post `
  -Form @{ file = Get-Item "D:\papers\Attention_Is_All_You_Need.pdf" }
```

Không lưu vào Obsidian trong request đó:

```powershell
Invoke-RestMethod `
  -Uri "http://127.0.0.1:8000/convert?save_to_obsidian=false" `
  -Method Post `
  -Form @{ file = Get-Item "D:\papers\Attention_Is_All_You_Need.pdf" }
```

## Response chính

```json
{
  "status": "success",
  "data": {
    "paper_title": "Attention Is All You Need",
    "metadata": {
      "title": "Attention Is All You Need",
      "authors": ["Ashish Vaswani"],
      "doi": null,
      "year": 2017,
      "abstract": "...",
      "keywords": null
    },
    "nodes": {
      "Abstract": "...",
      "Introduction": "..."
    },
    "raw_markdown": "# Attention Is All You Need\n...",
    "files": {
      "mmd_output": "D:\\...\\outputs\\Attention Is All You Need.mmd",
      "obsidian_note": "D:\\Obsidian\\MyVault\\Papers\\Attention Is All You Need.md"
    },
    "obsidian": {
      "saved": true,
      "reason": null,
      "path": "D:\\Obsidian\\MyVault\\Papers\\Attention Is All You Need.md"
    }
  }
}
```

## Biến môi trường

- `NOUGAT_CHECKPOINT`: đường dẫn model Nougat.
- `NOUGAT_BATCHSIZE`: batch size khi inference.
- `NOUGAT_CACHE_DIR`: thư mục cache tạm cho OCR.
- `PAPERTOOBSIDIAN_OUTPUT_DIR`: thư mục lưu `.mmd`.
- `OBSIDIAN_VAULT_PATH`: thư mục vault Obsidian.
- `OBSIDIAN_PAPERS_DIR`: thư mục con trong vault, mặc định `Papers`.
- `OBSIDIAN_SPLIT_NODES`: tạo note riêng cho từng section, mặc định `true`.
- `MAX_UPLOAD_MB`: dung lượng PDF tối đa, mặc định `80`.
