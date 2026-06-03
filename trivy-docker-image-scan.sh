#!/bin/bash

set -e

DOCKER_IMAGE_NAME=$(grep -m1 '^FROM' Dockerfile | awk '{print $2}')

if [[ -z "${DOCKER_IMAGE_NAME}" ]]; then
    echo "ERROR: Could not determine base image from Dockerfile."
    exit 1
fi

echo "=============================================="
echo "  Trivy Base Image Scan"
echo "  Image : ${DOCKER_IMAGE_NAME}"
echo "=============================================="

mkdir -p /tmp/trivy-cache

echo ""
echo "[1/2] Scanning for HIGH severity vulnerabilities..."

docker run --rm \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /tmp/trivy-cache:/root/.cache \
aquasec/trivy:latest \
image \
--exit-code 0 \
--severity HIGH \
--no-progress \
"${DOCKER_IMAGE_NAME}"

echo ""
echo "[2/2] Scanning for CRITICAL severity vulnerabilities..."

set +e

docker run --rm \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /tmp/trivy-cache:/root/.cache \
aquasec/trivy:latest \
image \
--exit-code 1 \
--severity CRITICAL \
--no-progress \
"${DOCKER_IMAGE_NAME}"

EXIT_CODE=$?

set -e

echo ""

if [[ "$EXIT_CODE" -eq 1 ]]; then
    echo "RESULT: FAILED — CRITICAL vulnerabilities found"
    exit 1
else
    echo "RESULT: PASSED — No CRITICAL vulnerabilities found"
fi