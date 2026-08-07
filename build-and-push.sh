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
PLATFORMS=""
CUSTOM_TAG=""

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
  echo "┃       AmneziaWG Easy (AWG) Build & Deployment Tool         ┃"
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
  echo "      --platform <plat>   Build for specific platform (e.g. linux/amd64,linux/arm64)"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                      # Test, build and push with default tag + latest"
  echo "  $0 --tag v1.0.0         # Test, build and push as shu1t3/wg-eas-awg3:v1.0.0 and :latest"
  echo "  $0 --no-push            # Test and build image locally without pushing"
  echo "  $0 --no-test --no-cache # Build without testing and without cache"
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
echo -e "${GREEN}✓ Docker is running.${NC}"

# Step 1: Run unit tests
if [ "${RUN_TESTS}" = true ]; then
  echo ""
  echo -e "${BLUE}[2/4] Running unit tests in isolated Node container...${NC}"
  if docker run --rm -v "${SCRIPT_DIR}:/app" -w /app/src node:22-alpine sh -c "corepack enable pnpm && pnpm install --frozen-lockfile && pnpm test"; then
    echo -e "${GREEN}✓ All unit tests passed successfully!${NC}"
  else
    echo -e "${RED}✗ Unit tests failed! Aborting build.${NC}"
    exit 1
  fi
else
  echo ""
  echo -e "${YELLOW}[2/4] Skipping unit tests (--no-test specified).${NC}"
fi

# Step 2: Build Docker image
echo ""
echo -e "${BLUE}[3/4] Building Docker image...${NC}"
echo -e "Image tags to create:"
echo -e "  - ${CYAN}${IMAGE_REPO}:${TAG}${NC}"
if [ "${TAG}" != "latest" ]; then
  echo -e "  - ${CYAN}${IMAGE_REPO}:latest${NC}"
fi

BUILD_ARGS=()
BUILD_ARGS+=("-t" "${IMAGE_REPO}:${TAG}")
if [ "${TAG}" != "latest" ]; then
  BUILD_ARGS+=("-t" "${IMAGE_REPO}:latest")
fi

if [ "${NO_CACHE}" = true ]; then
  BUILD_ARGS+=("--no-cache")
fi

if [ -n "${PLATFORMS}" ]; then
  BUILD_ARGS+=("--platform" "${PLATFORMS}")
fi

BUILD_ARGS+=(".")

if docker build "${BUILD_ARGS[@]}"; then
  echo -e "${GREEN}✓ Docker image built successfully!${NC}"
else
  echo -e "${RED}✗ Docker build failed!${NC}"
  exit 1
fi

# Verify binaries in built image
echo ""
echo -e "${BLUE}Verifying binaries inside the built image...${NC}"
docker run --rm "${IMAGE_REPO}:${TAG}" sh -c "
  echo -n '  - awg: ' && /usr/bin/awg --version &&
  echo -n '  - awg-quick: ' && which awg-quick &&
  echo -n '  - amneziawg-go: ' && which amneziawg-go
" || {
  echo -e "${RED}✗ Binary verification failed in built image!${NC}"
  exit 1
}
echo -e "${GREEN}✓ AmneziaWG binaries verified successfully.${NC}"

# Step 3: Push Docker image
if [ "${PUSH_IMAGE}" = true ]; then
  echo ""
  echo -e "${BLUE}[4/4] Pushing image to registry (${IMAGE_REPO})...${NC}"

  echo -e "Pushing ${CYAN}${IMAGE_REPO}:${TAG}${NC}..."
  docker push "${IMAGE_REPO}:${TAG}"

  if [ "${TAG}" != "latest" ]; then
    echo -e "Pushing ${CYAN}${IMAGE_REPO}:latest${NC}..."
    docker push "${IMAGE_REPO}:latest"
  fi

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✓ Image successfully pushed to registry!${NC}"
  echo -e "  Repository: ${CYAN}https://hub.docker.com/r/${IMAGE_REPO}${NC}"
  echo -e "  Tags:       ${CYAN}${TAG}${NC}"
  if [ "${TAG}" != "latest" ]; then
    echo -e "              ${CYAN}latest${NC}"
  fi
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
  echo ""
  echo -e "${YELLOW}[4/4] Skipping push (--no-push specified).${NC}"
  echo -e "${GREEN}✓ Image is ready locally: ${CYAN}${IMAGE_REPO}:${TAG}${NC}"
fi
