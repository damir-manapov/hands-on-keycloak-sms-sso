#!/usr/bin/env bash

set -euo pipefail

echo "▶ Formatting code with Prettier"
yarn format

echo "▶ Running ESLint"
yarn lint

echo "▶ Running TypeScript typecheck (src + tests)"
yarn typecheck

echo "▶ Building TypeScript project"
yarn build

echo "▶ Running security audit"
yarn audit

echo "▶ Checking for outdated dependencies"
yarn outdated

echo "▶ Running Java SPI verification"
mvn -f keycloak-providers/legacy-user-storage/pom.xml clean verify

echo "✅ All checks completed"
