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

# Compile the project
build:
    gleam build

# Run tests
test:
    gleam test

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
