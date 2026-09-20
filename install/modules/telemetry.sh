#!/usr/bin/env bash
# Telemetry is disabled in the Sidonia no Kishi fork.
# This stub accepts the upstream CLI so install.sh logic is untouched,
# but performs no network calls and collects nothing.

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --mode|-m) shift 2 ;;
        --version|-v) shift 2 ;;
        --old-version) shift 2 ;;
        --install-state) shift 2 ;;
        --compositor|-c) shift 2 ;;
        --id) shift 2 ;;
        --os) shift 2 ;;
        --enabled) shift 2 ;;
        --failed) shift 2 ;;
        --context) shift 2 ;;
        *) shift 1 ;;
    esac
done

exit 0