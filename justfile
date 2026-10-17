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
    gleam build --target erlang
    gleam build --target javascript

# Run tests
test:
    gleam test --target erlang
    gleam test --target javascript

# Run shared contracts in a real browser (install Chromium first)
test-browser:
    pnpm run test:browser

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
ci: lint test build test-browser

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
