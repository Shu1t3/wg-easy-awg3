#!/usr/bin/env bash

# ==============================================================================
# Build, Test & Push Script for AmneziaWG Easy (AWG)
# Repository / Image: shu1t3/wg-eas-awg3
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

IMAGE_REPO="shu1t3/wg-eas-awg3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Default parameters
RUN_TESTS=true
PUSH_IMAGE=true
NO_CACHE=false
DEFAULT_PLATFORMS="linux/amd64,linux/arm64"
PLATFORMS="${DEFAULT_PLATFORMS}"
CUSTOM_TAG=""
BUILDER_NAME="wg-easy-multiarch"

# Extract default version from src/package.json if available
DEFAULT_VERSION="latest"
if [ -f "src/package.json" ]; then
  EXTRACTED_VERSION=$(grep -m 1 '"version":' src/package.json | sed -E 's/.*"version": *"([^"]+)".*/\1/' || true)
  if [ -n "${EXTRACTED_VERSION}" ]; then
    DEFAULT_VERSION="${EXTRACTED_VERSION}"
  fi
fi

# Print helper banner
print_banner() {
  echo -e "${CYAN}"
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  echo "┃       AmneziaWG Easy (AWG) Multi-Arch Build & Deploy        ┃"
  echo "┃       Target Image: ${IMAGE_REPO}               ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  echo -e "${NC}"
}

# Print help message
show_help() {
  echo -e "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -t, --tag <tag>         Specify docker tag (default: extracted from src/package.json: '${DEFAULT_VERSION}')"
  echo "      --no-test           Skip running unit tests"
  echo "      --no-push           Build only, do not push to registry"
  echo "      --no-cache          Do not use cache when building the image"
  echo "      --platform <plat>   Target platforms (default: '${DEFAULT_PLATFORMS}')"
  echo "      --local             Build only for local host platform (loads into local docker daemon)"
  echo "      --builder <name>    Specify Buildx builder name (default: '${BUILDER_NAME}')"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                      # Test, build for linux/amd64 & linux/arm64, push manifest list"
  echo "  $0 --tag 15.4.0-shu1t3  # Build and push as shu1t3/wg-eas-awg3:15.4.0-shu1t3 and :latest"
  echo "  $0 --local              # Quick local build for current machine architecture only"
  echo "  $0 --no-push            # Multi-arch test build without pushing"
  echo "  $0 --no-test --no-cache # Build without running tests and without cache"
  exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)
      CUSTOM_TAG="$2"
      shift 2
      ;;
    --no-test)
      RUN_TESTS=false
      shift
      ;;
    --no-push)
      PUSH_IMAGE=false
      shift
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    --platform)
      PLATFORMS="$2"
      shift 2
      ;;
    --local|--single-arch)
      PLATFORMS="local"
      PUSH_IMAGE=false
      shift
      ;;
    --builder)
      BUILDER_NAME="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      show_help
      ;;
  esac
done

TAG="${CUSTOM_TAG:-${DEFAULT_VERSION}}"

print_banner

# Step 0: Pre-flight checks
echo -e "${BLUE}[1/4] Pre-flight checks...${NC}"
if ! command -v docker &> /dev/null; then
  echo -e "${RED}Error: docker is not installed or not in PATH.${NC}"
  exit 1
fi

if ! docker info &> /dev/null; then
  echo -e "${RED}Error: Docker daemon is not running or not accessible.${NC}"
  exit 1
fi

if ! docker buildx version &> /dev/null; then
  echo -e "${RED}Error: docker buildx plugin is not installed or not available.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Docker & Docker Buildx are ready.${NC}"

# Setup / verify Buildx builder for multi-platform support
ensure_builder() {
  if [ "${PLATFORMS}" = "local" ]; then
    return 0
  fi

  echo -e "${BLUE}Checking Docker Buildx builder '${BUILDER_NAME}'...${NC}"
  if ! docker buildx inspect "${BUILDER_NAME}" &> /dev/null; then
    echo -e "${YELLOW}Creating new multi-arch builder '${BUILDER_NAME}' with docker-container driver...${NC}"
    docker buildx create --name "${BUILDER_NAME}" --driver docker-container --bootstrap --use > /dev/null
  else
    docker buildx use "${BUILDER_NAME}" > /dev/null
  fi
  echo -e "${GREEN}✓ Using Buildx builder '${BUILDER_NAME}'.${NC}"
}

# Step 1: Run unit tests
if [ "${RUN_TESTS}" = true ]; then
  echo ""
  echo -e "${BLUE}[2/4] Running unit tests in isolated Node container...${NC}"
  if docker run --rm -v "${SCRIPT_DIR}:/app" -w /app/src node:22-alpine sh -c "npm install -g pnpm@11.19.0 --silent || corepack enable pnpm; pnpm install --frozen-lockfile && pnpm test"; then
    echo -e "${GREEN}✓ All unit tests passed successfully!${NC}"
  else
    echo -e "${RED}✗ Unit tests failed! Aborting build.${NC}"
    exit 1
  fi
else
  echo ""
  echo -e "${YELLOW}[2/4] Skipping unit tests (--no-test specified).${NC}"
fi

# Step 2: Build and publish Docker image
echo ""
echo -e "${BLUE}[3/4] Preparing Docker image build...${NC}"
echo -e "Image tags:"
echo -e "  - ${CYAN}${IMAGE_REPO}:${TAG}${NC}"
if [ "${TAG}" != "latest" ]; then
  echo -e "  - ${CYAN}${IMAGE_REPO}:latest${NC}"
fi

# Construct base build command with tags
BUILD_BASE_CMD=("docker" "buildx" "build")

if [ "${NO_CACHE}" = true ]; then
  BUILD_BASE_CMD+=("--no-cache")
fi

BUILD_BASE_CMD+=("-t" "${IMAGE_REPO}:${TAG}")
if [ "${TAG}" != "latest" ]; then
  BUILD_BASE_CMD+=("-t" "${IMAGE_REPO}:latest")
fi

if [ "${PLATFORMS}" = "local" ]; then
  echo -e "Target platform: ${CYAN}Local Host Architecture${NC}"
  echo -e "${BLUE}Building and loading local image into Docker daemon...${NC}"
  if "${BUILD_BASE_CMD[@]}" --load .; then
    echo -e "${GREEN}✓ Local Docker image built and loaded successfully!${NC}"
  else
    echo -e "${RED}✗ Local Docker build failed!${NC}"
    exit 1
  fi
else
  ensure_builder
  echo -e "Target platforms: ${CYAN}${PLATFORMS}${NC}"

  if [ "${PUSH_IMAGE}" = true ]; then
    echo -e "${BLUE}Building multi-platform image and pushing manifest list to registry...${NC}"
    if "${BUILD_BASE_CMD[@]}" --platform "${PLATFORMS}" --push .; then
      echo -e "${GREEN}✓ Multi-arch image and manifest list pushed successfully!${NC}"
    else
      echo -e "${RED}✗ Multi-arch Docker build & push failed!${NC}"
      exit 1
    fi
  else
    echo -e "${BLUE}Building multi-platform images (dry-run without push)...${NC}"
    if "${BUILD_BASE_CMD[@]}" --platform "${PLATFORMS}" .; then
      echo -e "${GREEN}✓ Multi-arch Docker build completed successfully!${NC}"
    else
      echo -e "${RED}✗ Multi-arch Docker build failed!${NC}"
      exit 1
    fi
  fi
fi

# Step 3: Verification & Summary
echo ""
echo -e "${BLUE}[4/4] Verification & Status...${NC}"

if [ "${PUSH_IMAGE}" = true ] && [ "${PLATFORMS}" != "local" ]; then
  echo -e "Inspecting pushed multi-architecture manifest for ${CYAN}${IMAGE_REPO}:${TAG}${NC}:"
  docker buildx imagetools inspect "${IMAGE_REPO}:${TAG}" || true

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✓ Multi-architecture image is LIVE on Docker Hub!${NC}"
  echo -e "  Repository: ${CYAN}https://hub.docker.com/r/${IMAGE_REPO}${NC}"
  echo -e "  Platforms:  ${CYAN}${PLATFORMS}${NC}"
  echo -e "  Tags:       ${CYAN}${TAG}${NC}"
  if [ "${TAG}" != "latest" ]; then
    echo -e "              ${CYAN}latest${NC}"
  fi
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
  echo -e "${YELLOW}Push skipped (--no-push or --local specified).${NC}"
  echo -e "${GREEN}✓ Image build verified for: ${CYAN}${PLATFORMS}${NC}"
fi
