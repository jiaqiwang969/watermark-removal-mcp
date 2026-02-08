#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="${REPO_DIR}/target/release/watermark-remover-mcp-server"

if [[ "${WATERMARK_MCP_AUTO_UPDATE:-0}" == "1" ]] && command -v git >/dev/null 2>&1; then
  git -C "${REPO_DIR}" pull --ff-only || true
fi

if [[ ! -x "${BIN_PATH}" || "${REPO_DIR}/src" -nt "${BIN_PATH}" ]]; then
  cargo build --release --manifest-path "${REPO_DIR}/Cargo.toml"
fi

export WATERMARK_SCRIPTS_DIR="${WATERMARK_SCRIPTS_DIR:-${REPO_DIR}/scripts}"
exec "${BIN_PATH}"
