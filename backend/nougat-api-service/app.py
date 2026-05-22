import os
import sys
import shutil
import re
from functools import partial
from http import HTTPStatus
from fastapi import FastAPI, File, UploadFile
from PIL import Image
from pathlib import Path
import hashlib
from fastapi.middleware.cors import CORSMiddleware
import pypdfium2
import torch
from nougat import NougatModel
from nougat.postprocessing import markdown_compatible, close_envs
from nougat.utils.dataset import ImageDataset
from nougat.utils.checkpoint import get_checkpoint
from nougat.dataset.rasterize import rasterize_paper
from nougat.utils.device import move_to_device, default_batch_size
from tqdm import tqdm

SAVE_DIR = Path("./pdfs")
# --- THÊM MỚI: Thư mục chuyên dùng để lưu các file .mmd thành phẩm ---
OUTPUT_DIR = Path("./outputs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

BATCHSIZE = int(os.environ.get("NOUGAT_BATCHSIZE", default_batch_size()))

NOUGAT_CHECKPOINT = get_checkpoint()
if NOUGAT_CHECKPOINT is None:
    print("Vui lòng set biến môi trường 'NOUGAT_CHECKPOINT' trỏ tới thư mục chứa model!")
    sys.exit(1)

app = FastAPI(title="Nougat PDF to Markdown API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
model = None

@app.on_event("startup")
async def load_model(checkpoint: str = NOUGAT_CHECKPOINT):
    global model, BATCHSIZE
    if model is None:
        model = NougatModel.from_pretrained(checkpoint)
        model = move_to_device(model, cuda=BATCHSIZE > 0)
        if BATCHSIZE <= 0:
            BATCHSIZE = 1
        model.eval()

def parse_markdown_to_nodes(markdown_text: str) -> dict:
    """Hàm băm nhỏ Markdown thành JSON phục vụ Obsidian"""
    lines = [line.strip() for line in markdown_text.split('\n') if line.strip()]
    
    # 1. Trích xuất Title 
    raw_title = lines[0].replace('#', '').strip() if lines else "Untitled Paper"
    safe_title = re.sub(r'[\\/*?:"<>|]', "", raw_title) 
    
    # 2. Tìm tất cả các thẻ Heading
    pattern = re.compile(r'^(#{1,3})\s+(.+)$', re.MULTILINE)
    matches = list(pattern.finditer(markdown_text))
    
    nodes = {}
    if not matches:
        nodes["Full_Content"] = markdown_text
    else:
        pre_text = markdown_text[:matches[0].start()].strip()
        if pre_text:
            nodes["Metadata_Frontmatter"] = pre_text
            
        for i in range(len(matches)):
            heading_text = matches[i].group(2).strip()
            key = re.sub(r'^\d+(\.\d+)*\s*', '', heading_text)
            
            start_idx = matches[i].end()
            end_idx = matches[i+1].start() if i + 1 < len(matches) else len(markdown_text)
            
            content = markdown_text[start_idx:end_idx].strip()
            if content:
                nodes[key] = content

    return {"title": safe_title, "nodes": nodes}

@app.get("/health")
def root():
    return {
        "status-code": HTTPStatus.OK,
        "data": {"message": "Nougat API is running!"},
    }

@app.post("/convert")
async def predict(file: UploadFile = File(...), start: int = None, stop: int = None) -> dict:
    pdfbin = file.file.read()
    pdf = pypdfium2.PdfDocument(pdfbin)
    md5 = hashlib.md5(pdfbin).hexdigest()
    save_path = SAVE_DIR / md5

    if start is not None and stop is not None:
        pages = list(range(start - 1, stop))
    else:
        pages = list(range(len(pdf)))
        
    predictions = [""] * len(pages)
    dellist = []
    
    if save_path.exists():
        for computed in (save_path / "pages").glob("*.mmd"):
            try:
                idx = int(computed.stem) - 1
                if idx in pages:
                    i = pages.index(idx)
                    predictions[i] = computed.read_text(encoding="utf-8")
                    dellist.append(idx)
            except Exception as e:
                print(e)
                
    compute_pages = pages.copy()
    for el in dellist:
        compute_pages.remove(el)
        
    images = rasterize_paper(pdf, pages=compute_pages)
    global model

    dataset = ImageDataset(images, partial(model.encoder.prepare_input, random_padding=False))
    dataloader = torch.utils.data.DataLoader(dataset, batch_size=BATCHSIZE, pin_memory=True, shuffle=False)

    for idx, sample in tqdm(enumerate(dataloader), total=len(dataloader)):
        if sample is None:
            continue
        model_output = model.inference(image_tensors=sample)
        for j, output in enumerate(model_output["predictions"]):
            if model_output["repeats"][j] is not None:
                if model_output["repeats"][j] > 0:
                    disclaimer = "\n\n+++ ==WARNING: Truncated because of repetitions==\n%s\n+++\n\n"
                else:
                    disclaimer = "\n\n+++ ==ERROR: No output for this page==\n%s\n+++\n\n"
                rest = close_envs(model_output["repetitions"][j]).strip()
                if len(rest) > 0:
                    disclaimer = disclaimer % rest
                else:
                    disclaimer = ""
            else:
                disclaimer = ""

            predictions[pages.index(compute_pages[idx * BATCHSIZE + j])] = markdown_compatible(output) + disclaimer

    final = "".join(predictions).strip()
    
    # --- PHÂN MẢNH THÔNG TIN ---
    parsed_data = parse_markdown_to_nodes(final)
    
    # --- LƯU FILE .MMD SẠCH RA THƯ MỤC OUTPUTS ---
    output_filename = f"{parsed_data['title']}.mmd"
    output_file_path = OUTPUT_DIR / output_filename
    output_file_path.write_text(final, encoding="utf-8")
    print(f"-> Đã lưu thành công file: {output_file_path}")
    
    # --- DỌN DẸP CACHE (Xóa ảnh rác để nhẹ máy) ---
    try:
        if save_path.exists():
            shutil.rmtree(save_path) 
    except Exception as e:
        print(f"Lỗi khi dọn dẹp cache: {e}")

    return {
        "status": "success",
        "data": {
            "paper_title": parsed_data["title"],
            "nodes": parsed_data["nodes"],
            "raw_markdown": final
        }
    }