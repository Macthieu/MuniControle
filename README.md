# MuniControle

MuniControle est l'outil specialise correspondant dans la suite documentaire municipale Orchiviste/Muni.

## Mission

Ce depot fournit un controle qualite documentaire deterministic en lecture seule, integre a la suite via le contrat canonique OrchivisteKit.

## Positionnement

- Outil autonome executables seul.
- Integrable dans Orchiviste (cockpit/hub) via contrat commun CLI JSON.

## Version

- Version de release: `0.2.0`
- Tag Git: `v0.2.0`

## Contrat CLI JSON V1

Commande:

```bash
muni-controle-cli run --request /path/request.json --result /path/result.json
```

Valeurs autorisees de `status`:

- `queued`
- `running`
- `succeeded`
- `failed`
- `needs_review`
- `cancelled`
- `not_implemented`

Statuts emis sur le chemin nominal V1:

- `succeeded`
- `needs_review`
- `failed`

Parametres canoniques supportes:

- `text` (string) ou `source_path` (string)
- `metadata_report_path` (string, optionnel)
- `preclassification_report_path` (string, optionnel)
- `analysis_report_path` (string, optionnel)
- `min_quality_score` (number, 0...100, optionnel, defaut 70)
- `output_report_path` (string, optionnel)

Comportement V1:

- outil strictement en lecture seule
- controle deterministic sans IA non deterministe
- rapport JSON optionnel exporte si `output_report_path` est fourni

## Build et tests

```bash
swift build
swift test
```

## Licence

GNU GPL v3.0, voir [LICENSE](LICENSE).
