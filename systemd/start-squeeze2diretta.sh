#!/bin/bash
# squeeze2diretta - Startup Wrapper Script
# This script reads configuration and starts squeeze2diretta with appropriate options

set -e

# Default values (can be overridden by config file)
LMS_SERVER="${LMS_SERVER:-192.168.1.100}"
TARGET="${TARGET:-1}"
PLAYER_NAME="${PLAYER_NAME:-squeeze2diretta}"
MAX_SAMPLE_RATE="${MAX_SAMPLE_RATE:-768000}"
DSD_FORMAT="${DSD_FORMAT:-:u32be}"
VERBOSE="${VERBOSE:-}"
EXTRA_OPTS="${EXTRA_OPTS:-}"

INSTALL_DIR="/opt/squeeze2diretta"
SQUEEZE2DIRETTA="$INSTALL_DIR/squeeze2diretta"
SQUEEZELITE="$INSTALL_DIR/squeezelite"

# Build command
CMD="$SQUEEZE2DIRETTA"
CMD="$CMD --squeezelite $SQUEEZELITE"
CMD="$CMD -s $LMS_SERVER"
CMD="$CMD --target $TARGET"
CMD="$CMD -n $PLAYER_NAME"
CMD="$CMD -r $MAX_SAMPLE_RATE"
# DSD format - only add if not empty
if [ -n "$DSD_FORMAT" ]; then
    CMD="$CMD -D $DSD_FORMAT"
fi

# Optional verbose mode
if [ -n "$VERBOSE" ]; then
    CMD="$CMD -v"
fi

# Extra options
if [ -n "$EXTRA_OPTS" ]; then
    CMD="$CMD $EXTRA_OPTS"
fi

# Log the command being executed
echo "════════════════════════════════════════════════════════"
echo "  Starting squeeze2diretta v1.0.0"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  LMS Server:       $LMS_SERVER"
echo "  Diretta Target:   $TARGET"
echo "  Player Name:      $PLAYER_NAME"
echo "  Max Sample Rate:  $MAX_SAMPLE_RATE"
echo "  DSD Format:       $DSD_FORMAT"
echo ""
echo "Command:"
echo "  $CMD"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""

# Execute
exec $CMD
