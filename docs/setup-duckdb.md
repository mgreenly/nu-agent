# DuckDB Setup and Management

## Overview

Nu-agent uses DuckDB for conversation persistence and requires the native library to be available for the Ruby gem to compile against.

The `bin/setup` script automatically handles DuckDB installation by:
1. Detecting your platform (Linux/macOS, x86_64/ARM)
2. Downloading pre-built DuckDB binaries from GitHub releases
3. Installing to `vendor/duckdb/` (local to the project)
4. Configuring bundler to compile the gem against these files

## Installation Locations

- **Library**: `vendor/duckdb/lib/libduckdb.so` (Linux) or `libduckdb.dylib` (macOS)
- **Headers**: `vendor/duckdb/include/duckdb.h` and `duckdb.hpp`
- **Version**: Currently v1.4.1
- **Ignored by git**: Yes, added to `.gitignore`

## Automatic Installation

Simply run:
```bash
bin/setup
```

This will:
- Check if DuckDB is already installed
- Verify the version matches the required version
- Download and install if needed or if version differs
- Configure bundler automatically
- Run `bundle install`

## Manual Installation

If you prefer to install DuckDB manually or use a different version:

### Option 1: Download Pre-built Binaries

```bash
# Set desired version
DUCKDB_VERSION="1.4.1"

# Detect platform
PLATFORM="linux-amd64"  # or "osx-universal", "linux-aarch64"

# Download
curl -L -o /tmp/libduckdb.zip \
  "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/libduckdb-${PLATFORM}.zip"

# Extract
unzip /tmp/libduckdb.zip -d /tmp/duckdb

# Install
mkdir -p vendor/duckdb/lib vendor/duckdb/include
cp /tmp/duckdb/libduckdb.* vendor/duckdb/lib/
cp /tmp/duckdb/duckdb.h* vendor/duckdb/include/

# Configure bundler (from project root)
bundle config build.duckdb \
  --with-duckdb-include=$(pwd)/vendor/duckdb/include \
  --with-duckdb-lib=$(pwd)/vendor/duckdb/lib
```

### Option 2: System Package Manager

```bash
# Debian/Ubuntu
sudo apt-get install libduckdb-dev

# macOS
brew install duckdb

# Then install gems normally
bundle install
```

## Updating DuckDB Version

To update to a new DuckDB version:

1. Edit `bin/setup` and change the `DUCKDB_VERSION` variable:
   ```bash
   DUCKDB_VERSION="1.5.0"  # Update to desired version
   ```

2. Run setup again:
   ```bash
   bin/setup
   ```

3. The script will detect the version mismatch and offer to reinstall

## Troubleshooting

### Version Mismatch Errors

If you see "Failed to execute prepared statement" or similar errors, there's likely a version mismatch between the DuckDB library and the Ruby gem.

**Solution**: Recompile the gem against your library:
```bash
# Uninstall the gem
gem uninstall duckdb --force

# Reinstall with proper configuration (from project root)
bundle config build.duckdb \
  --with-duckdb-include=$(pwd)/vendor/duckdb/include \
  --with-duckdb-lib=$(pwd)/vendor/duckdb/lib

bundle install
```

### Check Current Version

To verify which DuckDB version is being used:
```bash
ruby -rduckdb -e "db = DuckDB::Database.open; \
  conn = db.connect; \
  puts conn.query('PRAGMA version').to_a.first.first; \
  conn.close; db.close"
```

### Check Gem Native Extension Linkage

To see which library the Ruby gem is linked against:
```bash
ldd ~/.rvm/gems/ruby-*/extensions/*/duckdb-*/duckdb/duckdb_native.so | grep duckdb
```

### CI/CD Considerations

For GitHub Actions or other CI environments, the `bin/setup` script works without modification. It will automatically:
- Detect the runner platform
- Download the appropriate DuckDB binaries
- Configure bundler
- Install dependencies

No sudo access or system packages required.

## Platforms Supported

The automatic installer supports:
- Linux x86_64 (linux-amd64)
- Linux ARM64 (linux-aarch64)
- macOS Intel/Apple Silicon (osx-universal)

Other platforms will need manual installation from system packages.
