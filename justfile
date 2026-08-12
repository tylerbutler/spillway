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
# Releases are driven by changie: add a fragment with `just change`, and on
# merge to main a "Release X.Y.Z" PR is opened. Merging that PR tags the
# commit and creates the GitHub Release (no Hex publish).

alias ch := change

# Record a changelog entry for the current change
change:
    changie new

# Preview the version and changelog the next release would produce
changelog-preview:
    changie batch auto --dry-run

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
