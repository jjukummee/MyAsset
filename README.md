# account_agent

macOS SwiftUI app for personal asset/account management.

## Local configuration

Set these environment variables before running the Open Banking flow:

- `OPEN_BANKING_CLIENT_ID`
- `OPEN_BANKING_CLIENT_SECRET`
- `OPEN_BANKING_INSTITUTION_CODE`

For local transaction imports, run `bash run_import.command` from this checkout.
For an encrypted spreadsheet, set `MYASSET_IMPORT_PASSWORD` for a manual run or
keep the password in `~/Library/Application Support/MyAsset/import-password.txt`
with owner-only access for the LaunchAgent. Keep personal transaction exclusions
in the ignored `scripts/manual_excludes.json`.

The app reads `home-location.json` from `~/Library/Application Support/MyAsset/`.
Set `latitude`, `longitude` and `name` there to enable home detection.
Place local `weather.json`, `weather_current.json`, and `benefits.json` in the
same directory. `update_weather.py` uses `MYASSET_WEATHER_LOCATION` when set.
