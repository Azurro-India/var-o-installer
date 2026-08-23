# var-o-installer

Public bootstrap for **VAR-O1** on Windows edge boxes.

This repo is only the installer. It does **not** contain product source, YOLO weights, device tokens, or `Azurro-India/Main`.

## Install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/Azurro-India/var-o-installer/main/install.ps1 | iex
```

The script will ask for:

1. **Payload zip URL** — private edge release (not a git clone)
2. **Device token** — mint on the operator laptop with `varo token issue`

It then writes `C:\varo\.env`, installs NSSM service `AzurroVaroSampler`, and starts it.

Optional (no prompts):

```powershell
iex "& { $(irm https://raw.githubusercontent.com/Azurro-India/var-o-installer/main/install.ps1) } -PayloadUrl 'https://example/varo-edge.zip' -DeviceToken 'varo_...'"
```

## What lands on the box

```
C:\varo\
  bin\nssm.exe
  .venv\Scripts\varo.exe   (or bin\varo.exe — whatever the zip contains)
  models\yolo11m.pt
  logs\
  .env                     VARO_API_URL + VARO_DEVICE_TOKEN
  version.txt
```

Default API: `https://var-o1-api.onrender.com`

## Payload zip (built from Main, not this repo)

Must include a runnable `varo.exe` at one of:

- `varo.exe`
- `bin\varo.exe`
- `.venv\Scripts\varo.exe`

Should include `yolo11m.pt`. Must **not** include Scoresheets, tests, or `.git`.

There is no tag-built zip yet. Until CI exists, build one by hand and pass its URL.

## After install

Do **not** run interactive `varo run` while the service is RUNNING.

```powershell
sc query AzurroVaroSampler
Get-Content C:\varo\logs\varo-stdout.log -Tail 30
```

## Update

```powershell
irm https://raw.githubusercontent.com/Azurro-India/var-o-installer/main/update.ps1 | iex
```

Keeps `.env` and spool files. Replaces the payload and restarts the service.

## Security

- Public script on purpose. No GitHub PAT. No DB password.
- A box only works if it has a valid device token.
- Protect `main` on this repo: `irm | iex` as Admin means a push here is code execution on every box.
