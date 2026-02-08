# watermark-removal-mcp

Watermark Removal MCP server for Codex / MCP clients.

This server provides tools to:

- Convert PDF pages to PNG (`pdf_to_images`)
- Remove bottom-right watermarks from one image or a directory (`remove_watermark`)
- Merge images back to PDF (`images_to_pdf`)
- Run an end-to-end pipeline (`process_pdf`)

## How it works

The server is a small Rust MCP process that dispatches tool calls to Python scripts.

- Rust (`src/`) handles MCP JSON-RPC (`initialize`, `tools/list`, `tools/call`)
- Python (`scripts/`) does the heavy image/PDF processing
- `WATERMARK_SCRIPTS_DIR` controls where the Python scripts are loaded from

Watermark removal algorithm (OpenCV):

1. Focus on bottom-right ROI (watermark area)
2. Threshold light text in grayscale (`150..240`)
3. Dilate mask to connect text fragments
4. Inpaint with Telea algorithm

## Prerequisites

- Rust toolchain (`cargo`)
- Python 3.10+
- Poppler (`pdf2image` backend)
  - macOS: `brew install poppler`
  - Ubuntu: `sudo apt install poppler-utils`

Install Python dependencies:

```bash
pip install -r scripts/requirements.txt
```

## Run locally

Build and run:

```bash
cargo build --release
WATERMARK_SCRIPTS_DIR="$(pwd)/scripts" ./target/release/watermark-remover-mcp-server
```

Or use the helper script (builds automatically if needed):

```bash
./run-mcp.sh
```

Optional auto-update before start:

```bash
WATERMARK_MCP_AUTO_UPDATE=1 ./run-mcp.sh
```

## Codex CLI integration

After cloning this repo:

```bash
codex mcp add watermark-remover -- /absolute/path/to/watermark-removal-mcp/run-mcp.sh
```

This keeps your config simple and supports pulling latest code:

```bash
git -C /absolute/path/to/watermark-removal-mcp pull
```

## Tools

### `pdf_to_images`

```json
{
  "pdf_path": "/abs/path/input.pdf",
  "output_dir": "/abs/path/output_dir",
  "dpi": 200
}
```

### `remove_watermark`

```json
{
  "image_path": "/abs/path/image.png",
  "output_dir": "/abs/path/out_dir"
}
```

or

```json
{
  "image_dir": "/abs/path/images",
  "output_dir": "/abs/path/out_dir"
}
```

### `images_to_pdf`

```json
{
  "image_dir": "/abs/path/images",
  "output_path": "/abs/path/output.pdf",
  "pattern": "*.png"
}
```

### `process_pdf`

```json
{
  "pdf_path": "/abs/path/input.pdf",
  "images_output_dir": "/abs/path/work_dir",
  "dpi": 200
}
```

## License

MIT
