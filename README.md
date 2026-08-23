# var-o-installer

Public bootstrap for **VAR-O1** on Windows edge boxes.

This repo is only the installer. It does **not** contain product source, YOLO weights, device tokens, or `Azurro-India/Main`.

## Install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/Azurro-India/var-o-installer/main/install.ps1 | iex
```

You will be asked for:

1. **Payload zip URL** — HTTPS URL of `varo-edge.zip` (not a git clone, not a GitHub PAT)
2. **Device token** — `varo token issue` on the operator laptop

The script writes `C:\varo\.env`, creates a **local** Python 3.12 venv, installs CPU torch + the package, registers NSSM `AzurroVaroSampler`, and starts it.

Python **3.12** must already be on the box (`py -3.12`).

## How to get the payload URL (Main is private)

On your laptop (you are logged into GitHub):

```bash
# after Actions builds a release — tag varo-v0.2.0 or run workflow "Release edge zip"
gh release download varo-v0.2.0 -R Azurro-India/Main -p varo-edge.zip
```

Host that file somewhere the box can GET without a GitHub token (signed S3/Drive link you control). Paste that URL into the installer.

Do **not** put a GitHub PAT on the edge box.

## What lands on the box

```
C:\varo\
  app\ + pyproject.toml     from the zip
  .venv\Scripts\varo.exe    built on this machine
  models\yolo11m.pt
  bin\nssm.exe
  logs\
  .env                      VARO_API_URL + VARO_DEVICE_TOKEN + VARO_YOLO_MODEL
  version.txt
```

Default API: `https://var-o1-api.onrender.com`

## After install

Do **not** run interactive `varo run` while the service is RUNNING.

```powershell
sc query AzurroVaroSampler
Get-Content C:\varo\logs\varo-stdout.log -Tail 30
```

## Security

- Public script. No PAT. No DB password.
- Box only works with a valid device token.
- Protect `main` here: `irm | iex` as Admin is code execution on every box.
