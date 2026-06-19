# HALEEM-ULTRA — Test Releases (ريليس اختباري)

> ⚠️ هذا الريبو للاختبار فقط. لا تستخدم في الإنتاج.

## Quick Install

Run in **PowerShell as Administrator**:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/haleemrz/HALEEM-ULTRA-TestReleases/master/install.ps1 | iex
```

## What's Different from Production

| Feature | Production | This (Test) |
|---------|-----------|-------------|
| Arabic/Unicode usernames | ❌ May fail | ✅ Full support |
| Download fallbacks | 1 method | 4 methods |
| Extract fallbacks | 1 method | 5 methods |
| Python install fallbacks | 1 attempt | 3 attempts |
| FFmpeg Unicode fix | ❌ | ✅ Auto-copy to safe path |
| .venv Unicode fix | ❌ | ✅ Junction to C:\haleem-venv |
| Post-install verification | Basic (7 checks) | Comprehensive (38+ checks) |
| Package import testing | ❌ | ✅ Tests all 9 packages |
| `irm \| iex` compatibility | ❌ Breaks on PS 5.1 | ✅ Safe syntax |
| Silero VAD model patch | ❌ | ✅ Auto-patch for ai_models/ |

## Files

- `install.ps1` — Bulletproof installer v3.0
- `README.md` — This file
