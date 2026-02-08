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

## Runtime requirements

- Python 3.10+
- Poppler (`pdf2image` backend)
  - macOS: `brew install poppler`
  - Ubuntu: `sudo apt install poppler-utils`

Install Python dependencies:

```bash
pip install -r scripts/requirements.txt
```

## Quick start (recommended: NPX, no local scripts)

Run directly from GitHub with `npx`:

```bash
npx -y github:jiaqiwang969/watermark-removal-mcp
```

`run-mcp.sh` / `run-mcp.ps1` behavior:

- download prebuilt binary from GitHub Releases (latest by default)
- avoid local Rust compilation by default
- fallback to local binary if already present
- optional source build only when `WATERMARK_MCP_ALLOW_BUILD=1`

## Optional settings

Auto-update git repo before start:

```bash
WATERMARK_MCP_AUTO_UPDATE=1 ./run-mcp.sh
```

Pin a specific release:

```bash
WATERMARK_MCP_VERSION=v0.1.0 ./run-mcp.sh
```

Allow local build fallback (last resort):

```bash
WATERMARK_MCP_ALLOW_BUILD=1 ./run-mcp.sh
```

## Codex CLI integration

Use `npx` (cross-platform, no local `.sh` path):

```bash
codex mcp add watermark-remover -- npx -y github:jiaqiwang969/watermark-removal-mcp
```

### Legacy local launchers (optional)

If you still want local scripts instead of NPX:

- macOS/Linux: `run-mcp.sh`
- Windows: `run-mcp.ps1`

Clone:

```bash
git clone git@github.com:jiaqiwang969/watermark-removal-mcp.git
cd watermark-removal-mcp
```

Run MCP on macOS/Linux:

```bash
./run-mcp.sh
```

Run MCP on Windows:

```powershell
.\run-mcp.ps1
```

Keep up to date:

```bash
git -C /absolute/path/to/watermark-removal-mcp pull
```

## Release automation

This repo includes a release workflow:

- file: `.github/workflows/release.yml`
- trigger: push tags like `v0.1.0`
- output assets:
  - `watermark-remover-mcp-x86_64-unknown-linux-gnu.tar.gz`
  - `watermark-remover-mcp-x86_64-apple-darwin.tar.gz`
  - `watermark-remover-mcp-aarch64-apple-darwin.tar.gz`
  - `watermark-remover-mcp-x86_64-pc-windows-msvc.zip`

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
