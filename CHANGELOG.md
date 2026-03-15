# Changelog

Toutes les modifications notables de ce projet seront documentees dans ce fichier.

Le format s'inspire de Keep a Changelog et le projet suit Semantic Versioning.

## [Unreleased]

### Added
- Module `MuniControleInterop` base sur `OrchivisteKitContracts`.
- Runner V1 deterministic de controle qualite (lecture seule) avec score, gates et findings.
- CLI canonique active: `muni-controle-cli run --request <file> --result <file>`.
- Export optionnel de rapport JSON via `output_report_path`.
- Tests unitaires et interop couvrant les chemins `succeeded`, `needs_review` et `failed`.
- Versionnage de `Package.resolved` avec pin `OrchivisteKit` `0.2.0`.

## [0.1.0] - 2026-03-14

### Added
- Version initiale de normalisation du dépôt.
- README, CONTRIBUTING et licence harmonisés pour publication GitHub.
