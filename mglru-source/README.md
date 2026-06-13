# mglru-source/ — Raw MGLRU Source Files

Folder ini berisi **raw source files** implementasi MGLRU dari Android Common Kernel.
File-file ini adalah referensi untuk backport ke android12-5.10 GKI.

## File Map

### PRIMARY (inti implementasi)

| File | Deskripsi | Symbols Utama |
|------|-----------|---------------|
| `mm/vmscan.c` | Inti MGLRU — page reclaim | `lru_gen_shrink_lruvec()`, `multi_gen_lru_walk()` |
| `mm/workingset.c` | Refault distance tracking | `lru_gen_refault()` |
| `include/linux/mmzone.h` | Structs: lruvec, lru_gen_* | `struct lru_gen_folio`, `struct lruvec` |
| `include/linux/mm_inline.h` | Inline helpers | `lru_gen_add_folio()`, `lru_gen_del_folio()` |

### SECONDARY (integrasi)

| File | Deskripsi |
|------|-----------|
| `mm/Kconfig` | CONFIG_LRU_GEN, LRU_GEN_ENABLED, LRU_GEN_STATS |
| `mm/Kconfig.mglru-section` | Extract section LRU_GEN saja |
| `mm/memcontrol.c` | memcg + MGLRU integration |
| `include/linux/mm_types.h` | struct page additions |
| `kernel/sysctl.c` | /proc/sys/vm/lru_gen_enabled |

### diff/

Berisi full diff antara base (tanpa MGLRU) dan source (dengan MGLRU), per-file.
Gunakan ini sebagai panduan untuk apply perubahan ke fork kamu.

## Cara Backport ke android12-5.10

1. Lihat `diff/mm_vmscan.c.patch` — identifikasi blok kode MGLRU baru
2. Buka fork kamu di GitHub: `github.com/whiskiesweet/android_kernel_common-5.10/blob/android12-5.10/mm/vmscan.c`
3. Apply perubahan dari diff secara manual via GitHub editor
4. Atau jalankan `fetch-mglru-patches.yml` untuk patches yang sudah siap apply

## Config yang Dibutuhkan (sudah ada di build.sh kamu)

```
CONFIG_LRU_GEN=y
CONFIG_LRU_GEN_ENABLED=y
CONFIG_LRU_GEN_STATS=y
```


## Build Info

- Source branch  : `android13-5.10`
- Base branch    : `android12-5.10`
- Folio compat   : `yes`
- Dry-run result : ✓7 clean | △0 fuzzy | ✗0 conflict
- Generated      : 2026-06-13 11:17 UTC
