# Squeezelite Setup for squeeze2diretta

## Problem

The standard squeezelite binary outputs silence (zeros) when stdout is redirected to a pipe because `fwrite()` buffers data when stdout is not a terminal.

## Solution

Apply the provided patch to squeezelite source code to add `fflush(stdout)` after each write operation.

## Steps

### 1. Clone squeezelite

```bash
git clone https://github.com/ralph-irving/squeezelite.git
cd squeezelite
```

### 2. Apply the patch

```bash
patch -p1 < ../squeezelite-stdout-flush.patch
```

### 3. Compile

On Debian/Ubuntu:
```bash
sudo apt install build-essential libasound2-dev libflac-dev libvorbis-dev \
                 libmad0-dev libmpg123-dev libopus-dev libsoxr-dev libssl-dev
make OPTS="-DRESAMPLE -DNO_FAAD"
```

On Fedora/RHEL:
```bash
sudo dnf install gcc make alsa-lib-devel flac-devel libvorbis-devel \
                 libmad-devel mpg123-devel opus-devel soxr-devel openssl-devel
make OPTS="-DRESAMPLE -DNO_FAAD"
```

### 4. Install

```bash
sudo cp squeezelite /usr/local/bin/
```

Or copy to your preferred location specified in squeeze2diretta configuration.

## Verification

Test that the patch works:

```bash
./squeezelite -o - -r 44100 | head -c 1000 | od -A x -t x1 | head
```

You should see non-zero audio data, not all zeros.
