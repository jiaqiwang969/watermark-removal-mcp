#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_REPO="${WATERMARK_MCP_GITHUB_REPO:-jiaqiwang969/watermark-removal-mcp}"
BIN_NAME="watermark-remover-mcp-server"
VERSION="${WATERMARK_MCP_VERSION:-latest}"
CACHE_BASE="${WATERMARK_MCP_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/watermark-removal-mcp}"
LOCAL_BIN_PATH="${REPO_DIR}/target/release/${BIN_NAME}"

detect_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64)
      arch="x86_64"
      ;;
    arm64|aarch64)
      arch="aarch64"
      ;;
    *)
      echo "Unsupported CPU architecture: ${arch}" >&2
      return 1
      ;;
  esac

  case "${os}" in
    Darwin)
      echo "${arch}-apple-darwin"
      ;;
    Linux)
      if [[ "${arch}" == "aarch64" ]]; then
        echo "Linux aarch64 prebuilt binary is not published yet." >&2
        return 1
      fi
      echo "${arch}-unknown-linux-gnu"
      ;;
    *)
      echo "Unsupported OS for run-mcp.sh: ${os}" >&2
      return 1
      ;;
  esac
}

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --silent --show-error --output "${out}" "${url}"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="${out}" "${url}"
    return 0
  fi

  echo "Neither curl nor wget found; cannot download prebuilt binary." >&2
  return 1
}

resolve_release_url() {
  local target="$1"
  local asset="watermark-remover-mcp-${target}.tar.gz"
  if [[ "${VERSION}" == "latest" ]]; then
    echo "https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
    return
  fi

  local normalized_version="${VERSION}"
  if [[ "${normalized_version}" != v* ]]; then
    normalized_version="v${normalized_version}"
  fi
  echo "https://github.com/${GITHUB_REPO}/releases/download/${normalized_version}/${asset}"
}

install_prebuilt_if_missing() {
  local target="$1"
  local install_dir="${CACHE_BASE}/${VERSION}/${target}"
  local bin_path="${install_dir}/bin/${BIN_NAME}"

  if [[ -x "${bin_path}" ]]; then
    echo "${bin_path}"
    return 0
  fi

  local tmp_dir archive_path download_url
  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/bundle.tar.gz"
  download_url="$(resolve_release_url "${target}")"

  if ! download_file "${download_url}" "${archive_path}"; then
    rm -rf "${tmp_dir}"
    return 1
  fi

  mkdir -p "${tmp_dir}/unpack"
  tar -xzf "${archive_path}" -C "${tmp_dir}/unpack"

  local extracted_dir
  extracted_dir="$(find "${tmp_dir}/unpack" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${extracted_dir}" ]]; then
    echo "Downloaded archive missing payload directory." >&2
    rm -rf "${tmp_dir}"
    return 1
  fi

  mkdir -p "${install_dir}"
  cp -R "${extracted_dir}/." "${install_dir}/"
  chmod +x "${bin_path}" || true
  rm -rf "${tmp_dir}"

  if [[ ! -x "${bin_path}" ]]; then
    echo "Downloaded binary is missing or not executable: ${bin_path}" >&2
    return 1
  fi

  echo "${bin_path}"
}

if [[ "${WATERMARK_MCP_AUTO_UPDATE:-0}" == "1" ]] && command -v git >/dev/null 2>&1; then
  git -C "${REPO_DIR}" pull --ff-only || true
fi

TARGET="$(detect_target)"
BIN_PATH=""

if BIN_PATH="$(install_prebuilt_if_missing "${TARGET}")"; then
  :
elif [[ -x "${LOCAL_BIN_PATH}" ]]; then
  BIN_PATH="${LOCAL_BIN_PATH}"
elif [[ "${WATERMARK_MCP_ALLOW_BUILD:-0}" == "1" ]]; then
  cargo build --release --manifest-path "${REPO_DIR}/Cargo.toml"
  BIN_PATH="${LOCAL_BIN_PATH}"
else
  echo "Unable to find prebuilt binary for ${TARGET} and no local binary exists." >&2
  echo "Either publish/download a release, or set WATERMARK_MCP_ALLOW_BUILD=1 once." >&2
  exit 1
fi

if [[ -n "${WATERMARK_SCRIPTS_DIR:-}" ]]; then
  export WATERMARK_SCRIPTS_DIR
elif [[ -d "${REPO_DIR}/scripts" ]]; then
  export WATERMARK_SCRIPTS_DIR="${REPO_DIR}/scripts"
else
  BIN_DIR="$(cd "$(dirname "${BIN_PATH}")" && pwd)"
  if [[ -d "${BIN_DIR}/../scripts" ]]; then
    export WATERMARK_SCRIPTS_DIR="${BIN_DIR}/../scripts"
  else
    echo "Cannot find scripts directory. Set WATERMARK_SCRIPTS_DIR explicitly." >&2
    exit 1
  fi
fi

exec "${BIN_PATH}"
