#!/bin/bash
# Bhromon — Local Development Setup Script (Unix/macOS)

set -e

RED='\033[0;31%'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Setting up Bhromon Development Environment   ${NC}"
echo -e "${GREEN}=========================================${NC}"

# 1. Check Flutter
echo -e "\n${YELLOW}[1/4] Checking Flutter installation...${NC}"
if command -v flutter &> /dev/null; then
    echo -e "${GREEN}Flutter is installed: $(flutter --version | head -n 1)${NC}"
else
    echo -e "${RED}Flutter SDK not found. Please install Flutter and add it to your PATH.${NC}"
    exit 1
fi

# 2. Install Melos
echo -e "\n${YELLOW}[2/4] Installing/updating Melos globally...${NC}"
dart pub global activate melos

# 3. Bootstrap workspace
echo -e "\n${YELLOW}[3/4] Running Melos bootstrap...${NC}"
export PATH="$PATH":"$HOME/.pub-cache/bin"
melos bootstrap

# 4. Generate generated files
echo -e "\n${YELLOW}[4/4] Running code generator...${NC}"
melos run build_runner

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}  Setup completed successfully!${NC}"
echo -e "${GREEN}  Run 'flutter run' to start the application.${NC}"
echo -e "${GREEN}=========================================${NC}"
