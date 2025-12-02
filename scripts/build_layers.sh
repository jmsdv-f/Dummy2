#!/bin/bash

set -e

PYTHON_VERSION="3.12"
AWS_LAMBDA_IMAGE="public.ecr.aws/lambda/python:${PYTHON_VERSION}"
LAYERS_DIR=("infrastructure/core/lambdas/layers" "infrastructure/support/lambdas/layers")
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}==========================================${NC}"
    echo -e "${BLUE}Lambda Layer Builder${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}Python Version: ${PYTHON_VERSION}${NC}"
    echo -e "${BLUE}AWS Lambda Image: ${AWS_LAMBDA_IMAGE}${NC}"
    echo -e "${BLUE}Project Root: ${PROJECT_ROOT}${NC}"
    echo "${BLUE}==========================================${NC}"
}

check_docker() {
    echo "Checking Docker availability..."
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}✗ Error: Docker is not running.${NC}"
        echo "  Please start Docker and try again."
        exit 1
    fi
    echo -e "${GREEN}✓ Docker is running${NC}"
}

build_layer() {
    local layer_path=$1
    local layer_name=$(basename "$layer_path")
    local abs_layer_path=$(cd "$layer_path" && pwd)
    
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Building layer: ${layer_name}${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Display requirements
    echo "  📄 Requirements:"
    while IFS= read -r line || [ -n "$line" ]; do
        echo "    - $line"
    done < "${layer_path}/requirements.txt"
    echo ""
    
    # Clean previous build
    echo "  🧹 Cleaning previous build..."
    rm -rf "${layer_path}/python"
    
    # Run pip install inside the Lambda container
    if docker run --rm \
        --entrypoint "" \
        -v "${abs_layer_path}:/var/task" \
        -w /var/task \
        "${AWS_LAMBDA_IMAGE}" \
        pip install -r requirements.txt \
            -t "python" \
            --no-cache-dir \
            --upgrade 2>&1; then
        
        # Verify the build
        if [ -d "${layer_path}/python" ] && [ "$(ls -A ${layer_path}/python)" ]; then
            echo -e "\n${GREEN}  ✓ Successfully built ${layer_name}${NC}"
            return 0
        else
            echo -e "${RED}  ✗ Failed to build ${layer_name}${NC}"
            return 1
        fi
    else
        echo -e "${RED}  ✗ Docker build failed for ${layer_name}${NC}"
        return 1
    fi
}

main() {
    print_header
    check_docker
    
    # Change to project root
    cd "${PROJECT_ROOT}"
    
    local target_layer="$1"

    if [ -n "$target_layer" ]; then
        # Search for the layer in all layer directories
        local found=false
        for layers_dir in "${LAYERS_DIR[@]}"; do
            local layer_path="${layers_dir}/${target_layer}"
            
            if [ -d "${layer_path}" ]; then
                if [ ! -f "${layer_path}/requirements.txt" ]; then
                    echo -e "${RED}✗ Error: ${target_layer} has no requirements.txt${NC}"
                    exit 1
                fi
                
                build_layer "${layer_path}" || exit 1

                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            echo -e "${RED}✗ Error: Layer '${target_layer}' not found in any layer directory${NC}"
            exit 1
        fi
    else
        # Build all layers
        echo " Building all layers..."
        echo "🔍 Searching for layers in ${LAYERS_DIR}..."
        local layer_count=0
        local skipped_count=0
        local failed_layers=()

        for layers_dir in "${LAYERS_DIR[@]}"; do
            for layer_path in "${layers_dir}"/*; do
                if [ -d "${layer_path}" ]; then
                    # Check if requirements.txt exists
                    if [ ! -f "${layer_path}/requirements.txt" ]; then
                        echo -e "\n${YELLOW}⊘ Skipping $(basename ${layer_path}): no requirements.txt found${NC}"
                        skipped_count=$((skipped_count + 1))
                        continue
                    fi

                    if build_layer "${layer_path}"; then
                        layer_count=$((layer_count + 1))
                    else
                        failed_layers+=("$(basename ${layer_path})")
                    fi
                fi
            done
        done

        if [ ${layer_count} -eq 0 ] && [ ${#failed_layers[@]} -eq 0 ]; then
            echo -e "${YELLOW}No layers found in ${LAYERS_DIR}${NC}"
            exit 0
        fi

        # Print summary
        echo -e "\n${BLUE}=========================================="
        echo "Build Summary"
        echo -e "==========================================${NC}"
        

        echo "✓ Successfully built: ${layer_count} layer(s)"
        echo "⊘ Skipped: ${skipped_count} layer(s)"

        if [ ${#failed_layers[@]} -gt 0 ]; then
            echo -e "${RED}✗ Failed: ${#failed_layers[@]} layer(s)${NC}"
            for layer in "${failed_layers[@]}"; do
                echo "  - ${layer}"
            done
            exit 1
        fi
        
        echo -e "${BLUE}==========================================${NC}\n"
    fi
    
    exit 0
}

# Run main function
main "$@"
