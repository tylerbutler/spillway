# Type-safe Fluid Framework protocol logic (Gleam)

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias l := lint
alias c := clean

# Default recipe
default:
    @just --list

# === STANDARD RECIPES ===

# Download dependencies
deps:
    gleam deps download

# Compile the project
build:
    gleam build

# Build with warnings as errors
build-strict:
    gleam build --warnings-as-errors

# Type check without building
check:
    gleam check

# Run tests
test:
    gleam test

# Build documentation
docs:
    gleam docs build

# Format code
format:
    gleam format

# Check formatting
lint:
    gleam format --check

# Remove build artifacts
clean:
    rm -rf build

# Full validation workflow
ci: format lint test build

alias pr := ci

# === RELEASE ===

# Bump the version, tag it, and push (CI creates the GitHub Release; no Hex publish)
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree is not clean; commit or stash changes first." >&2
        exit 1
    fi
    sd '^version = ".*"' 'version = "{{version}}"' gleam.toml
    git add gleam.toml
    git commit -m "chore(release): v{{version}}"
    git tag -a "v{{version}}" -m "Release v{{version}}"
    git push origin HEAD "v{{version}}"
    echo "Pushed v{{version}} — the Release workflow will create the GitHub Release."

# === SITE ===

# Build the Astro site
site-build:
    pnpm run build

# Run the Astro dev server
site-dev:
    pnpm run dev

# Preview the built site
site-preview:
    pnpm run preview
