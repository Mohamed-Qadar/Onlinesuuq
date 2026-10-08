# Onlinesuuq

**Dukaankaaga, gacantaada. — Your shop, in your hands.**

Onlinesuuq helps independent Somali sellers create a shop, add products, share a shop code and manage orders. Customers can order without registering. The native Flutter client supports Somali (default) and English; Django REST Framework and PostgreSQL provide the shared backend.

## Windows download status

**A working public installer is not available yet.** The live backend has not been deployed. Source code and installer packaging are available, but installing a client alone will not enable sign-in or orders.

Windows installation is designed to use one `Onlinesuuq-Setup.exe`: no Python, Docker or database installation is required on the customer's PC. The server is hosted separately. There is no automatic payment collection; sellers verify direct payments themselves.

## Build and publish

- [Windows build and installer instructions (Turkish)](docs/WINDOWS_RELEASE.md)
- Ready Inno Setup script: [`packaging/windows/Onlinesuuq.iss`](packaging/windows/Onlinesuuq.iss)
- Local build: `packaging/windows/Build-Setup.ps1 -ApiUrl https://YOUR_REAL_API_HOST/api/v1/`
- GitHub **Actions → Build Windows Setup → Run workflow** accepts a live API URL, checks it, runs Flutter checks, builds the installer and optionally creates a **draft** release. The workflow is manual; pushing code does not start a build or publish a release.
- Test the draft installer on a clean Windows PC before publishing it. No installer build or Windows installation is currently claimed as verified.

## Project

- `mobile/`: Flutter 3.47.6 / Dart 3.13.5, Android and Windows runners.
- `backend/`: Python 3.12.14, Django 5.2.18, PostgreSQL API and admin.
- `packaging/windows/`: per-user English installation wizard, shortcuts and bundled runtime helpers.
- `docs/`: setup, API, release and validation notes.

[Local development guide (Turkish)](docs/LOCAL_DEVELOPMENT_TR.md) · [API documentation](docs/API.md) · [Test record](docs/TEST_RESULTS.md) · [Pilot limits](docs/PILOT.md)

Keep `.env`, private signing keys, tokens, database dumps, uploaded customer files and local databases out of Git. Release configuration includes only the public HTTPS API address. Never embed server secrets in the desktop client.
