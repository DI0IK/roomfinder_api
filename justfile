# Justfile for Roomfinder API
# Run `just` to see all available commands

default:
    @just --list

# Run tests
test:
    gleam test

# Run compiler and static type checker
check:
    gleam check

# Auto-format all code
format:
    gleam format src test

# Check code formatting (linter)
lint:
    gleam format --check src test

# Run the API server locally
dev:
    gleam run

# Build a production shipment (deployment bundle)
build:
    gleam export erlang-shipment
