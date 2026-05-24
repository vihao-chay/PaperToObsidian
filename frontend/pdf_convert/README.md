# PDF to Obsidian Knowledge Nodes

Flutter Desktop frontend for selecting a PDF, validating an Obsidian vault, previewing backend analysis, and exporting Markdown nodes.

## Run

```powershell
flutter pub get
flutter run -d windows
```

The default backend base URL is `http://127.0.0.1:8000` and can be edited inside the app.

## API Calls

- `POST /analyze`: multipart form with `file`, `pdf_path`, and `vault_path`.
- `POST /export`: JSON body with `analysis_id` when available, plus `pdf_path`, `vault_path`, and `output_folder`. If no `analysis_id` is returned by analyze, the frontend sends the parsed analysis payload under `analysis`.

The vault is considered valid only when the selected folder contains a `.obsidian` directory.
