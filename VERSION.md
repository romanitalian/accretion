# Version registry

Single source of truth for the release version. `make gen` (and every build target) copies it into
`project.yml` via [`scripts/sync_version.py`](scripts/sync_version.py). Do not remove the fence markers.

| Key | App Store Connect / Xcode | Notes |
|-----|---------------------------|-------|
| `MARKETING_VERSION` | **Version** (CFBundleShortVersionString) | e.g. `1.0.0` |
| `APP_BUILD` | **Build** (CFBundleVersion) | Strictly increasing; `make bump` adds 1 |

```version-registry
MARKETING_VERSION=1.0.0
APP_BUILD=1
```

## What's New in 1.0.0

- First release.
