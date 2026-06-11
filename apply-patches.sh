#!/bin/bash

PATCH_DIR="../kernel-patches"

if [ ! -d "$PATCH_DIR" ]; then
    echo "△ Folder kernel-patches/ tidak ditemukan — skip"
    exit 0
fi

PATCH_LIST=$(find "$PATCH_DIR" -maxdepth 1 -name "*.patch" | sort)
if [ -z "$PATCH_LIST" ]; then
    echo "△ Tidak ada file .patch — skip"
    exit 0
fi

FAILED=0
for patch in $PATCH_LIST; do
    PNAME=$(basename "$patch")
    OUT=$(mktemp)
    
    echo "Mencoba menerapkan: $PNAME..."
    if patch -p1 --forward --fuzz=3 < "$patch" > "$OUT" 2>&1; then
        echo "✓ Berhasil: $PNAME"
    else
        if grep -q "Reversed (or previously applied)" "$OUT"; then
            echo "△ Sudah ada/Pernah diterapkan (skip OK): $PNAME"
        else
            echo "✗ GAGAL: $PNAME"
            cat "$OUT"
            
            find . -name "*.rej" | head -5 | xargs -I{} sh -c 'echo "REJ: {}"; cat {}'
            FAILED=$((FAILED + 1))
        fi
    fi
    rm -f "$OUT"
done

if [ "$FAILED" -ne 0 ]; then
    echo "=================================================="
    echo "⚠️ Ada $FAILED patch yang GAGAL diterapkan!"
    echo "=================================================="
    exit 1 
fi

echo "✓ Semua custom patches sukses diterapkan!"
exit 0

