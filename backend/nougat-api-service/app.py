import hashlib
import json
import os
import re
import shutil
import uuid
from datetime import datetime, timezone
from functools import partial
from http import HTTPStatus
from pathlib import Path
from typing import Any, Optional

import pypdfium2
import torch
from fastapi import Body, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from nougat import NougatModel
from nougat.dataset.rasterize import rasterize_paper
from nougat.postprocessing import close_envs, markdown_compatible
from nougat.utils.checkpoint import get_checkpoint
from nougat.utils.dataset import ImageDataset
from nougat.utils.device import default_batch_size, move_to_device
from tqdm import tqdm


BASE_DIR = Path(__file__).resolve().parent


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")

        if key and key not in os.environ:
            os.environ[key] = os.path.expandvars(value)


load_env_file(BASE_DIR / ".env")

SAVE_DIR = Path(os.environ.get("NOUGAT_CACHE_DIR", BASE_DIR / "pdfs")).resolve()
OUTPUT_DIR = Path(os.environ.get("PAPERTOOBSIDIAN_OUTPUT_DIR", BASE_DIR / "outputs")).resolve()
ANALYSIS_DIR = Path(os.environ.get("PAPERTOOBSIDIAN_ANALYSIS_DIR", OUTPUT_DIR / "analyses")).resolve()

OBSIDIAN_VAULT_PATH = os.environ.get("OBSIDIAN_VAULT_PATH")
OBSIDIAN_PAPERS_DIR = os.environ.get("OBSIDIAN_PAPERS_DIR", "Papers")
OBSIDIAN_SPLIT_NODES = os.environ.get("OBSIDIAN_SPLIT_NODES", "true").lower() not in {"0", "false", "no"}
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "80"))
MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024
BATCHSIZE = int(os.environ.get("NOUGAT_BATCHSIZE", default_batch_size()))

SAVE_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
ANALYSIS_DIR.mkdir(parents=True, exist_ok=True)

INVALID_FILENAME_CHARS = re.compile(r'[\\/*?:"<>|\[\]#^]')
DOI_PATTERN = re.compile(r"\b10\.\d{4,9}/[-._;()/:A-Z0-9]+\b", re.IGNORECASE)
YEAR_PATTERN = re.compile(r"\b(19|20)\d{2}\b")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.+)$", re.MULTILINE)
ANALYSIS_ID_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,120}$")

app = FastAPI(title="PaperToObsidian Nougat API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

model: Optional[NougatModel] = None
startup_error: Optional[str] = None


def clean_markdown_heading(value: str) -> str:
    value = re.sub(r"^\s*#+\s*", "", value)
    value = re.sub(r"[*_`]+", "", value)
    return value.strip()


def safe_filename(value: str, fallback: str = "Untitled Paper", max_length: int = 120) -> str:
    cleaned = INVALID_FILENAME_CHARS.sub("", value).strip().strip(".")
    cleaned = re.sub(r"\s+", " ", cleaned)
    if not cleaned:
        cleaned = fallback
    return cleaned[:max_length].rstrip()


def next_available_path(path: Path) -> Path:
    if not path.exists():
        return path

    stem = path.stem
    suffix = path.suffix
    parent = path.parent

    for index in range(2, 1000):
        candidate = parent / f"{stem} ({index}){suffix}"
        if not candidate.exists():
            return candidate

    raise HTTPException(status_code=500, detail="Cannot create a unique output filename.")


def unique_node_key(nodes: dict[str, str], key: str) -> str:
    base_key = re.sub(r"^\d+(\.\d+)*\s*", "", clean_markdown_heading(key)) or "Section"
    candidate = base_key
    index = 2

    while candidate in nodes:
        candidate = f"{base_key}_{index}"
        index += 1

    return candidate


def extract_title(markdown_text: str, fallback_title: str) -> str:
    for line in markdown_text.splitlines():
        line = clean_markdown_heading(line)
        if line:
            return line
    return fallback_title or "Untitled Paper"


def extract_section_text(nodes: dict[str, str], section_name: str) -> Optional[str]:
    normalized_target = section_name.lower()
    for key, value in nodes.items():
        normalized_key = key.lower().strip()
        if normalized_key == normalized_target or normalized_key.startswith(f"{normalized_target} "):
            return value.strip()
    return None


def extract_authors(markdown_text: str, title: str) -> list[str]:
    lines = [clean_markdown_heading(line) for line in markdown_text.splitlines()]
    lines = [line for line in lines if line]

    candidates: list[str] = []
    title_seen = False

    for line in lines[:30]:
        lowered = line.lower()
        if line == title:
            title_seen = True
            continue
        if lowered in {"abstract", "introduction", "keywords"}:
            break
        if lowered.startswith(("abstract", "doi", "keywords", "received", "accepted")):
            break
        if title_seen and not DOI_PATTERN.search(line) and len(line) <= 240:
            candidates.append(line)
        if len(candidates) >= 3:
            break

    if not candidates:
        return []

    author_blob = " ".join(candidates)
    author_blob = re.sub(r"\$.*?\$", "", author_blob)
    author_blob = re.sub(r"\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b", "", author_blob)
    author_blob = re.sub(r"\s+", " ", author_blob).strip(" ,;")

    if not author_blob:
        return []

    pieces = re.split(r"\s+and\s+|;|,(?=\s+[A-Z])", author_blob)
    authors = [piece.strip(" ,") for piece in pieces if piece.strip(" ,")]
    return authors[:20]


def extract_metadata(markdown_text: str, title: str, nodes: dict[str, str]) -> dict[str, Any]:
    doi_match = DOI_PATTERN.search(markdown_text)
    year_match = YEAR_PATTERN.search(markdown_text[:5000])

    return {
        "title": title,
        "authors": extract_authors(markdown_text, title),
        "doi": doi_match.group(0).rstrip(".,;") if doi_match else None,
        "year": int(year_match.group(0)) if year_match else None,
        "abstract": extract_section_text(nodes, "Abstract"),
        "keywords": extract_section_text(nodes, "Keywords"),
    }


def parse_markdown_to_nodes(markdown_text: str, fallback_title: str) -> dict[str, Any]:
    title = extract_title(markdown_text, fallback_title)
    filename_title = safe_filename(title)
    matches = list(HEADING_PATTERN.finditer(markdown_text))

    nodes: dict[str, str] = {}
    if not matches:
        nodes["Full_Content"] = markdown_text
    else:
        pre_text = markdown_text[: matches[0].start()].strip()
        if pre_text:
            nodes["Metadata_Frontmatter"] = pre_text

        for index, match in enumerate(matches):
            heading_text = match.group(2).strip()
            key = unique_node_key(nodes, heading_text)
            start_idx = match.end()
            end_idx = matches[index + 1].start() if index + 1 < len(matches) else len(markdown_text)
            content = markdown_text[start_idx:end_idx].strip()
            if content:
                nodes[key] = content

    metadata = extract_metadata(markdown_text, title, nodes)
    return {"title": title, "safe_title": filename_title, "nodes": nodes, "metadata": metadata}


def resolve_vault_path(vault_path: str) -> Path:
    if not vault_path or not vault_path.strip():
        raise HTTPException(status_code=400, detail="vault_path is required.")

    resolved = Path(vault_path).expanduser().resolve()
    if not resolved.exists() or not resolved.is_dir():
        raise HTTPException(status_code=400, detail=f"Vault folder does not exist: {resolved}")

    if not (resolved / ".obsidian").is_dir():
        raise HTTPException(status_code=400, detail=f"Invalid Obsidian vault, missing .obsidian: {resolved}")

    return resolved


def resolve_output_folder(vault_path: Path, output_folder: Optional[str] = None) -> Path:
    if not output_folder:
        return vault_path / OBSIDIAN_PAPERS_DIR

    resolved = Path(output_folder).expanduser().resolve()
    try:
        relative = resolved.relative_to(vault_path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="output_folder must be inside the selected vault.") from exc

    if relative.parts and relative.parts[0].lower() == ".obsidian":
        raise HTTPException(status_code=400, detail="output_folder cannot be inside .obsidian.")

    return resolved


def split_text_items(value: Optional[Any], separator_pattern: str = r"[,;\n]+") -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]

    text = str(value).strip()
    if not text:
        return []

    return [item.strip() for item in re.split(separator_pattern, text) if item.strip()]


def is_metadata_node(section_name: str, paper_title: str = "") -> bool:
    normalized = clean_markdown_heading(section_name).lower().replace("_", " ")
    normalized = re.sub(r"\s+", " ", normalized).strip()
    normalized_title = clean_markdown_heading(paper_title).lower()

    if normalized_title and normalized == normalized_title:
        return True

    return normalized in {
        "abstract",
        "keywords",
        "references",
        "bibliography",
        "metadata frontmatter",
    }


def extract_references(nodes: dict[str, str]) -> list[str]:
    references_text = (
        extract_section_text(nodes, "References")
        or extract_section_text(nodes, "Bibliography")
        or ""
    )
    if not references_text:
        return []

    blocks = [block.strip() for block in re.split(r"\n\s*\n", references_text) if block.strip()]
    if len(blocks) > 1:
        return blocks

    lines = [line.strip(" -\t") for line in references_text.splitlines() if line.strip(" -\t")]
    return lines or [references_text.strip()]


def build_sections_preview(nodes: dict[str, str], paper_title: str) -> list[dict[str, str]]:
    sections: list[dict[str, str]] = []
    for section_name, section_content in nodes.items():
        if not section_content.strip():
            continue
        if is_metadata_node(section_name, paper_title):
            continue
        if section_name == "Full_Content":
            sections.append({"title": "Full Content", "content": section_content})
        else:
            sections.append({"title": section_name, "content": section_content})
    return sections


def build_nodes_preview(
    nodes: dict[str, str],
    metadata: dict[str, Any],
    target_dir: Path,
) -> list[dict[str, str]]:
    paper_title = metadata.get("title") or "Untitled Paper"
    note_title = safe_filename(paper_title)
    planned_nodes = [
        {
            "title": paper_title,
            "type": "paper",
            "path": str(target_dir / f"{note_title}.md"),
        }
    ]

    if not OBSIDIAN_SPLIT_NODES:
        return planned_nodes

    section_dir = target_dir / note_title
    for section_name, section_content in nodes.items():
        if not section_content.strip():
            continue
        if is_metadata_node(section_name, paper_title) or section_name == "Full_Content":
            continue
        planned_nodes.append(
            {
                "title": section_name,
                "type": "section",
                "path": str(section_dir / f"{safe_filename(section_name, fallback='Section')}.md"),
            }
        )

    return planned_nodes


def analysis_path(analysis_id: str) -> Path:
    if not ANALYSIS_ID_PATTERN.fullmatch(analysis_id):
        raise HTTPException(status_code=400, detail="Invalid analysis_id.")
    return ANALYSIS_DIR / f"{analysis_id}.json"


def save_analysis_payload(payload: dict[str, Any]) -> None:
    path = analysis_path(payload["analysis_id"])
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def load_analysis_payload(analysis_id: str) -> dict[str, Any]:
    path = analysis_path(analysis_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"analysis_id not found: {analysis_id}")

    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"Stored analysis is invalid JSON: {analysis_id}") from exc

    if not isinstance(loaded, dict):
        raise HTTPException(status_code=500, detail=f"Stored analysis is invalid: {analysis_id}")

    return loaded


def build_analysis_payload(
    parsed_data: dict[str, Any],
    raw_markdown: str,
    source_filename: str,
    vault_path: Path,
    output_folder: Path,
    mmd_output_path: Path,
    analysis_id: str,
) -> dict[str, Any]:
    metadata = dict(parsed_data["metadata"])
    keywords = split_text_items(metadata.get("keywords"))
    metadata["keywords"] = keywords
    nodes = parsed_data["nodes"]
    title = parsed_data["title"]

    return {
        "analysis_id": analysis_id,
        "title": title,
        "paper_title": title,
        "authors": metadata.get("authors") or [],
        "keywords": keywords,
        "abstract": metadata.get("abstract") or "",
        "sections": build_sections_preview(nodes, title),
        "references": extract_references(nodes),
        "nodes_to_create": build_nodes_preview(nodes, metadata, output_folder),
        "nodes": nodes,
        "metadata": metadata,
        "markdown_preview": raw_markdown,
        "raw_markdown": raw_markdown,
        "output_folder": str(output_folder),
        "vault_path": str(vault_path),
        "source_filename": source_filename,
        "files": {
            "mmd_output": str(mmd_output_path),
            "analysis": str(analysis_path(analysis_id)),
        },
    }


def yaml_string(value: Optional[Any]) -> str:
    if value is None or value == "":
        return '""'
    text = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{text}"'


def obsidian_alias(value: str) -> str:
    return value.replace("|", "-").replace("[", "(").replace("]", ")").strip()


def obsidian_link(vault_path: Path, note_path: Path, alias: Optional[str] = None) -> str:
    link_path = note_path.relative_to(vault_path).with_suffix("").as_posix()
    if alias:
        return f"[[{link_path}|{obsidian_alias(alias)}]]"
    return f"[[{link_path}]]"


def build_obsidian_note(
    markdown_text: str,
    metadata: dict[str, Any],
    source_filename: str,
    section_links: Optional[list[tuple[str, str]]] = None,
) -> str:
    imported_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    title = metadata.get("title") or "Untitled Paper"
    authors = metadata.get("authors") or []
    year = metadata.get("year")
    doi = metadata.get("doi")
    abstract = metadata.get("abstract")

    year_line = str(year) if year else '""'

    frontmatter_lines = [
        "---",
        f"title: {yaml_string(title)}",
    ]
    if authors:
        frontmatter_lines.append("authors:")
        frontmatter_lines.extend(f"  - {yaml_string(author)}" for author in authors)
    else:
        frontmatter_lines.append("authors: []")
    frontmatter_lines.extend(
        [
            f"year: {year_line}",
            f"doi: {yaml_string(doi)}",
            f"source_pdf: {yaml_string(source_filename)}",
            f"imported_at: {yaml_string(imported_at)}",
            "tags:",
            "  - paper",
            "  - imported/nougat",
            "---",
        ]
    )
    frontmatter = "\n".join(frontmatter_lines)

    metadata_lines = [
        f"# {title}",
        "",
        "## Summary",
        "",
        "## Key Points",
        "",
        "- ",
        "",
    ]

    if section_links:
        metadata_lines.extend(["## Section Nodes", ""])
        metadata_lines.extend(f"- {link}" for _, link in section_links)
        metadata_lines.append("")

    metadata_lines.extend(
        [
        "## Questions",
        "",
        "- ",
        "",
        "## Paper Metadata",
        "",
        f"- Authors: {', '.join(authors) if authors else ''}",
        f"- Year: {year or ''}",
        f"- DOI: {doi or ''}",
        f"- Source PDF: {source_filename}",
        ]
    )

    if abstract:
        metadata_lines.extend(["", "## Abstract", "", abstract])

    metadata_lines.extend(["", "## Extracted Content", "", markdown_text.strip()])
    return frontmatter + "\n\n" + "\n".join(metadata_lines).rstrip() + "\n"


def build_section_note(
    section_name: str,
    section_content: str,
    metadata: dict[str, Any],
    source_filename: str,
    parent_link: str,
) -> str:
    imported_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    paper_title = metadata.get("title") or "Untitled Paper"
    title = f"{paper_title} - {section_name}"

    frontmatter = "\n".join(
        [
            "---",
            f"title: {yaml_string(title)}",
            f"paper: {yaml_string(paper_title)}",
            f"section: {yaml_string(section_name)}",
            f"source_pdf: {yaml_string(source_filename)}",
            f"imported_at: {yaml_string(imported_at)}",
            "tags:",
            "  - paper-section",
            "  - imported/nougat",
            "---",
        ]
    )

    body = "\n".join(
        [
            f"# {section_name}",
            "",
            f"Paper: {parent_link}",
            "",
            section_content.strip(),
        ]
    )
    return frontmatter + "\n\n" + body.rstrip() + "\n"


def save_section_notes(
    vault_path: Path,
    target_dir: Path,
    main_note_path: Path,
    nodes: dict[str, str],
    metadata: dict[str, Any],
    source_filename: str,
) -> list[dict[str, str]]:
    if not OBSIDIAN_SPLIT_NODES:
        return []

    paper_title = safe_filename(metadata.get("title") or "Untitled Paper")
    normalized_paper_title = clean_markdown_heading(metadata.get("title") or "").lower()
    section_dir = target_dir / paper_title
    section_dir.mkdir(parents=True, exist_ok=True)
    parent_link = obsidian_link(vault_path, main_note_path, metadata.get("title") or paper_title)
    section_notes: list[dict[str, str]] = []

    for section_name, section_content in nodes.items():
        if section_name in {"Metadata_Frontmatter", "Full_Content"}:
            continue
        if clean_markdown_heading(section_name).lower() == normalized_paper_title:
            continue
        if not section_content.strip():
            continue

        section_path = next_available_path(section_dir / f"{safe_filename(section_name, fallback='Section')}.md")
        section_path.write_text(
            build_section_note(section_name, section_content, metadata, source_filename, parent_link),
            encoding="utf-8",
        )
        section_notes.append(
            {
                "title": section_name,
                "path": str(section_path),
                "link": obsidian_link(vault_path, section_path, section_name),
            }
        )

    return section_notes


def save_obsidian_note(
    markdown_text: str,
    metadata: dict[str, Any],
    nodes: dict[str, str],
    source_filename: str,
) -> dict[str, Any]:
    if not OBSIDIAN_VAULT_PATH:
        return {
            "saved": False,
            "reason": "Set OBSIDIAN_VAULT_PATH to enable saving notes directly into an Obsidian vault.",
            "path": None,
        }

    vault_path = Path(OBSIDIAN_VAULT_PATH).expanduser().resolve()
    if not vault_path.exists() or not vault_path.is_dir():
        raise HTTPException(
            status_code=500,
            detail=f"OBSIDIAN_VAULT_PATH does not exist or is not a directory: {vault_path}",
        )

    target_dir = vault_path / OBSIDIAN_PAPERS_DIR
    target_dir.mkdir(parents=True, exist_ok=True)

    note_title = safe_filename(metadata.get("title") or "Untitled Paper")
    note_path = next_available_path(target_dir / f"{note_title}.md")

    section_notes = save_section_notes(vault_path, target_dir, note_path, nodes, metadata, source_filename)
    section_links = [(item["title"], item["link"]) for item in section_notes]
    note_path.write_text(
        build_obsidian_note(markdown_text, metadata, source_filename, section_links),
        encoding="utf-8",
    )

    return {
        "saved": True,
        "reason": None,
        "path": str(note_path),
        "section_nodes_saved": len(section_notes),
        "section_nodes": section_notes,
    }


def save_obsidian_note_to_vault(
    markdown_text: str,
    metadata: dict[str, Any],
    nodes: dict[str, str],
    source_filename: str,
    vault_path: Path,
    target_dir: Optional[Path] = None,
) -> dict[str, Any]:
    target_dir = target_dir or vault_path / OBSIDIAN_PAPERS_DIR
    target_dir.mkdir(parents=True, exist_ok=True)

    note_title = safe_filename(metadata.get("title") or "Untitled Paper")
    note_path = next_available_path(target_dir / f"{note_title}.md")

    section_notes = save_section_notes(vault_path, target_dir, note_path, nodes, metadata, source_filename)
    section_links = [(item["title"], item["link"]) for item in section_notes]
    note_path.write_text(
        build_obsidian_note(markdown_text, metadata, source_filename, section_links),
        encoding="utf-8",
    )

    return {
        "saved": True,
        "reason": None,
        "path": str(note_path),
        "section_nodes_saved": len(section_notes),
        "section_nodes": section_notes,
    }


def validate_upload(file: UploadFile, pdfbin: bytes) -> None:
    filename = file.filename or ""
    if not filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")

    if len(pdfbin) == 0:
        raise HTTPException(status_code=400, detail="Uploaded PDF is empty.")

    if len(pdfbin) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail=f"PDF is larger than {MAX_UPLOAD_MB} MB.")

    if not pdfbin.startswith(b"%PDF"):
        raise HTTPException(status_code=400, detail="Uploaded file does not look like a valid PDF.")


def resolve_pages(total_pages: int, start: Optional[int], stop: Optional[int]) -> list[int]:
    if total_pages <= 0:
        raise HTTPException(status_code=400, detail="PDF has no pages.")

    if start is None and stop is None:
        return list(range(total_pages))

    if start is None or stop is None:
        raise HTTPException(status_code=400, detail="Both start and stop must be provided together.")

    if start > stop:
        raise HTTPException(status_code=400, detail="start must be less than or equal to stop.")

    if start < 1 or stop > total_pages:
        raise HTTPException(status_code=400, detail=f"Page range must be between 1 and {total_pages}.")

    return list(range(start - 1, stop))


def ensure_model_ready() -> NougatModel:
    if model is None:
        message = startup_error or "Nougat model is not loaded yet."
        raise HTTPException(status_code=503, detail=message)
    return model


def run_nougat(pdf: pypdfium2.PdfDocument, pdfbin: bytes, pages: list[int]) -> str:
    loaded_model = ensure_model_ready()
    md5 = hashlib.md5(pdfbin).hexdigest()
    save_path = SAVE_DIR / md5
    predictions = [""] * len(pages)
    cached_pages: list[int] = []

    if save_path.exists():
        for computed in (save_path / "pages").glob("*.mmd"):
            try:
                page_index = int(computed.stem) - 1
                if page_index in pages:
                    prediction_index = pages.index(page_index)
                    predictions[prediction_index] = computed.read_text(encoding="utf-8")
                    cached_pages.append(page_index)
            except Exception as exc:
                print(f"Cannot read cached page {computed}: {exc}")

    compute_pages = [page for page in pages if page not in cached_pages]
    images = rasterize_paper(pdf, pages=compute_pages) if compute_pages else []

    if images:
        dataset = ImageDataset(images, partial(loaded_model.encoder.prepare_input, random_padding=False))
        dataloader = torch.utils.data.DataLoader(
            dataset,
            batch_size=BATCHSIZE,
            pin_memory=True,
            shuffle=False,
        )

        for batch_index, sample in tqdm(enumerate(dataloader), total=len(dataloader)):
            if sample is None:
                continue
            model_output = loaded_model.inference(image_tensors=sample)
            for sample_index, output in enumerate(model_output["predictions"]):
                output_page_index = batch_index * BATCHSIZE + sample_index
                if output_page_index >= len(compute_pages):
                    continue

                disclaimer = ""
                if model_output["repeats"][sample_index] is not None:
                    if model_output["repeats"][sample_index] > 0:
                        disclaimer_template = "\n\n+++ ==WARNING: Truncated because of repetitions==\n%s\n+++\n\n"
                    else:
                        disclaimer_template = "\n\n+++ ==ERROR: No output for this page==\n%s\n+++\n\n"
                    rest = close_envs(model_output["repetitions"][sample_index]).strip()
                    if rest:
                        disclaimer = disclaimer_template % rest

                page_number = compute_pages[output_page_index]
                predictions[pages.index(page_number)] = markdown_compatible(output) + disclaimer

    for image in images:
        try:
            image.close()
        except Exception:
            pass

    try:
        if save_path.exists():
            shutil.rmtree(save_path)
    except Exception as exc:
        print(f"Cannot clean cache {save_path}: {exc}")

    return "".join(predictions).strip()


@app.on_event("startup")
async def load_model() -> None:
    global model, BATCHSIZE, startup_error

    if model is not None:
        return

    checkpoint = os.environ.get("NOUGAT_CHECKPOINT") or get_checkpoint()
    if checkpoint is None:
        startup_error = "Set NOUGAT_CHECKPOINT to the directory that contains the Nougat model."
        print(startup_error)
        return

    try:
        model = NougatModel.from_pretrained(checkpoint)
        model = move_to_device(model, cuda=BATCHSIZE > 0)
        if BATCHSIZE <= 0:
            BATCHSIZE = 1
        model.eval()
        startup_error = None
    except Exception as exc:
        startup_error = f"Cannot load Nougat model: {exc}"
        print(startup_error)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status-code": HTTPStatus.OK,
        "data": {
            "message": "PaperToObsidian API is running.",
            "model_loaded": model is not None,
            "model_error": startup_error,
            "obsidian_vault_configured": bool(OBSIDIAN_VAULT_PATH),
            "obsidian_papers_dir": OBSIDIAN_PAPERS_DIR,
            "obsidian_split_nodes": OBSIDIAN_SPLIT_NODES,
            "output_dir": str(OUTPUT_DIR),
            "analysis_dir": str(ANALYSIS_DIR),
        },
    }


@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...),
    vault_path: str = Form(...),
    output_folder: Optional[str] = Form(default=None),
    pdf_path: Optional[str] = Form(default=None),
    start: Optional[int] = Query(default=None, ge=1),
    stop: Optional[int] = Query(default=None, ge=1),
) -> dict[str, Any]:
    resolved_vault_path = resolve_vault_path(vault_path)
    output_folder = resolve_output_folder(resolved_vault_path, output_folder)

    pdfbin = await file.read()
    validate_upload(file, pdfbin)

    try:
        pdf = pypdfium2.PdfDocument(pdfbin)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Cannot read PDF: {exc}") from exc

    pages = resolve_pages(len(pdf), start, stop)
    raw_markdown = run_nougat(pdf, pdfbin, pages)

    source_filename = file.filename or (Path(pdf_path).name if pdf_path else "Untitled Paper.pdf")
    fallback_title = Path(source_filename).stem
    parsed_data = parse_markdown_to_nodes(raw_markdown, fallback_title=fallback_title)

    output_file_path = next_available_path(OUTPUT_DIR / f"{parsed_data['safe_title']}.mmd")
    output_file_path.write_text(raw_markdown, encoding="utf-8")

    analysis_id = f"{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:12]}"
    analysis_payload = build_analysis_payload(
        parsed_data=parsed_data,
        raw_markdown=raw_markdown,
        source_filename=source_filename,
        vault_path=resolved_vault_path,
        output_folder=output_folder,
        mmd_output_path=output_file_path,
        analysis_id=analysis_id,
    )
    save_analysis_payload(analysis_payload)

    return {
        "status": "success",
        "data": analysis_payload,
    }


@app.post("/export")
async def export(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
    analysis: dict[str, Any]
    analysis_id = payload.get("analysis_id")
    if analysis_id:
        analysis = load_analysis_payload(str(analysis_id))
    else:
        raw_analysis = payload.get("analysis")
        if not isinstance(raw_analysis, dict):
            raise HTTPException(status_code=400, detail="analysis_id or analysis payload is required.")
        analysis = raw_analysis

    vault_path_value = payload.get("vault_path") or analysis.get("vault_path")
    resolved_vault_path = resolve_vault_path(str(vault_path_value or ""))
    output_folder = resolve_output_folder(
        resolved_vault_path,
        str(payload.get("output_folder") or analysis.get("output_folder") or ""),
    )

    raw_markdown = str(analysis.get("raw_markdown") or analysis.get("markdown_preview") or "")
    if not raw_markdown.strip():
        raise HTTPException(status_code=400, detail="Analysis payload does not contain raw_markdown.")

    metadata = analysis.get("metadata")
    if not isinstance(metadata, dict):
        metadata = {}
    metadata = dict(metadata)
    metadata["title"] = metadata.get("title") or analysis.get("title") or analysis.get("paper_title") or "Untitled Paper"
    metadata["authors"] = metadata.get("authors") or analysis.get("authors") or []
    metadata["keywords"] = metadata.get("keywords") or analysis.get("keywords") or []
    metadata["abstract"] = metadata.get("abstract") or analysis.get("abstract")

    nodes = analysis.get("nodes")
    if not isinstance(nodes, dict):
        nodes = {
            section.get("title", f"Section {index + 1}"): section.get("content", "")
            for index, section in enumerate(analysis.get("sections") or [])
            if isinstance(section, dict)
        }
    nodes = {str(key): str(value) for key, value in nodes.items() if str(value).strip()}

    source_filename = (
        analysis.get("source_filename")
        or (Path(str(payload.get("pdf_path"))).name if payload.get("pdf_path") else None)
        or f"{safe_filename(metadata['title'])}.pdf"
    )

    obsidian_result = save_obsidian_note_to_vault(
        raw_markdown,
        metadata,
        nodes,
        str(source_filename),
        resolved_vault_path,
        output_folder,
    )

    files_created = [obsidian_result["path"]]
    files_created.extend(item["path"] for item in obsidian_result.get("section_nodes", []))

    return {
        "status": "success",
        "data": {
            "export_success": True,
            "success": True,
            "nodes_created": len(files_created),
            "folder_path": str(output_folder),
            "files_created": files_created,
            "path": obsidian_result["path"],
            "section_nodes": obsidian_result.get("section_nodes", []),
        },
    }


@app.post("/convert")
async def convert(
    file: UploadFile = File(...),
    start: Optional[int] = Query(default=None, ge=1),
    stop: Optional[int] = Query(default=None, ge=1),
    save_to_obsidian: bool = Query(default=True),
) -> dict[str, Any]:
    pdfbin = await file.read()
    validate_upload(file, pdfbin)

    try:
        pdf = pypdfium2.PdfDocument(pdfbin)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Cannot read PDF: {exc}") from exc

    pages = resolve_pages(len(pdf), start, stop)
    raw_markdown = run_nougat(pdf, pdfbin, pages)

    fallback_title = Path(file.filename or "Untitled Paper").stem
    parsed_data = parse_markdown_to_nodes(raw_markdown, fallback_title=fallback_title)

    output_file_path = next_available_path(OUTPUT_DIR / f"{parsed_data['safe_title']}.mmd")
    output_file_path.write_text(raw_markdown, encoding="utf-8")

    obsidian_result = {"saved": False, "reason": "save_to_obsidian=false", "path": None}
    if save_to_obsidian:
        obsidian_result = save_obsidian_note(
            raw_markdown,
            parsed_data["metadata"],
            parsed_data["nodes"],
            file.filename or f"{parsed_data['safe_title']}.pdf",
        )

    return {
        "status": "success",
        "data": {
            "paper_title": parsed_data["title"],
            "metadata": parsed_data["metadata"],
            "nodes": parsed_data["nodes"],
            "raw_markdown": raw_markdown,
            "files": {
                "mmd_output": str(output_file_path),
                "obsidian_note": obsidian_result["path"],
            },
            "obsidian": obsidian_result,
        },
    }
