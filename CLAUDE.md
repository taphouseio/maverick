# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Maverick is a Swift-based blog engine built on Vapor 4 that reads content from [textbundle](https://textbundle.org/spec) directories. It's a hybrid between static sites (files on disk) and dynamic sites (server-rendered), with no database required.

**Stack:** Swift 6.2, Vapor 4.121.0, Leaf templating, SwiftMarkdown

## Build Commands

```bash
# Build
swift build                    # Debug build
swift build -c release         # Release build

# Test
swift test                     # Run all tests

# Development
make dev                       # Download dev site (jsorge.net) into _dev/
make run                       # Run Maverick locally via swift run
make docker-dev                # Build & run in Docker with nginx
make docker-dev-down           # Stop Docker dev containers

# Production Docker (ghcr.io/jsorge/maverick)
make docker-build              # Build container image
make docker-push               # Push to GitHub Container Registry
```

**Dependencies:** On macOS, requires `pkg-config` and `libressl` via Homebrew. On Linux, requires `libssl-dev` and `pkg-config`.

**Docker:** Production image uses `swift:6.2-noble` for building and `ubuntu:24.04` for runtime.

## Architecture

### Module Structure

- **Maverick** (`Sources/Maverick/`): Executable entry point
- **MaverickLib** (`Sources/MaverickLib/`): Core application logic (controllers, routes, helpers)
- **MaverickModels** (`Sources/MaverickModels/`): Data models (reusable as a library)
- **Micropub** (`Sources/Micropub/`): Micropub protocol implementation

### Content Model

Content is stored in textbundle directories:
```
YYYY-MM-DD-slug.textbundle/
├── info.json      # Metadata including io_taphouse_maverick extension
├── text.md        # Markdown content
└── assets/        # Images referenced in text.md
```

Content locations are defined in `PathHelper.Location` enum:
- `.posts` → `Public/_posts/` (published posts)
- `.pages` → `Public/_pages/` (static pages)
- `.drafts` → `Public/_drafts/` (unpublished)

### Request Flow

1. Route match in `routes.swift` (RouteCollections: `PostListRouteCollection`, `SinglePostRouteCollection`, `StaticPageRouter`, `TagController`)
2. Controller fetches content via `FileReader` → `TextBundleReader`
3. `BasePost` created from textbundle, converted to `Post` with HTML content via `FileProcessor`
4. `Page` view model created combining post(s) with `SiteConfig`
5. Leaf template renders response

### Key Patterns

- **No database**: Pure filesystem-based content
- **Polling for changes**: 10-second intervals for feed regeneration and route updates (see `configure.swift` `runRepeatedTask`)
- **Observer pattern**: `SiteContentChangeResponderManager` notifies responders (like `SitePinger`) when content changes
- **Image rewriting**: `FileProcessor.relinkImagesInText()` transforms `assets/` paths to full URLs

### Feed Generation

`FeedOutput.makeAllTheFeeds()` runs on timer, generating:
- RSS and JSON feeds
- Full-text and microblog variants
- Output to `Public/feeds/`

When feeds change, `SitePinger` notifies configured URLs (micro.blog webhooks).

## Development Setup

The `_dev/` directory (gitignored) contains a real Maverick site used for development. It's downloaded from the jsorge.net repository via `make dev`.

**Project structure:**
```
maverick/
├── Sources/                        # Engine code
├── Dockerfile                      # Production image only
├── tools/
│   ├── update_dev.sh              # Downloads dev site
│   └── docker-compose_local.yml   # Dev Docker config
└── _dev/                          # Dev site (.gitignored)
    ├── Public/_posts/             # Blog content
    ├── Resources/Views/           # Leaf templates
    ├── SiteConfig.yml             # Site configuration
    └── .tools/                    # Site's deployment tooling
```

**Development workflow:**
```bash
make dev          # First time: download dev site into _dev/
make run          # Run via swift (fastest iteration, no Docker)
make docker-dev   # Run in Docker with nginx (tests production build)
```

The `make run` command runs Maverick directly via `swift run`, serving content from `_dev/`. The `make docker-dev` command builds the production Dockerfile and runs it with nginx, useful for testing the Docker build before pushing.

## Configuration

`SiteConfig.yml` controls site metadata, batch sizes, feed settings, and template cache behavior. Loaded by `SiteConfigController` and decoded into `SiteConfig` model.

## Extension Points

- **New content types**: Add to `PathHelper.Location` enum
- **New feed formats**: Implement `FeedGenerator` protocol
- **New routes**: Create `RouteCollection` and register in `routes.swift`
- **Content change handlers**: Implement `SiteContentChangeResponder` protocol
