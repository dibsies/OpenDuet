# Publication privacy gate

The public source starts with fresh neutral authorship: OpenDuet Contributors
and contributors@example.invalid. Private development history and recovery
artifacts are excluded. Only the reviewed public checkout may be pushed.

Before publishing, audit the exact source tree/archive, Git history, app and
all DMG contents. Exclude personal names/email, account paths, hostnames,
serial numbers/device UIDs, credentials, raw diagnostics/captures, recordings,
private media, installer backups, quarantine sessions and vendor binaries.
Preserve legally required upstream attribution. Generated application artwork
contains no private photographs or desktop captures.

Releases strip debug information and map source paths. The app bundles its
source revision; the source ZIP matches that revision. tools/privacy-audit.py
checks identity/path/key/token patterns, archive entries and neutral history.
Pattern scans supplement manual content/metadata review; they are not proof
against every possible identifier. Scan the actual packaged payload as well
as the repository. Checksums and a release manifest identify reviewed files.

GitHub account/profile identity remains visible according to account settings.
HTTPS versus SSH does not anonymize a public profile or commit metadata.
No global Git settings, credentials or account/profile settings are changed
by preparation. Local private history must never be pushed, even if its tip
uses a neutral author.
