# Native display language

`AppLanguage` reports the bundle's English or Simplified Chinese selection and combines it with the device region for formatting. The native app uses it to present assignment dates and the saved semester selector. It must not translate school-authored text or change schools, identity scopes or timestamps. No service or stored preferences.

Inputs: bundled languages and device region. Outputs: `isEnglish` and `locale`. Consumers: the root scene and native date formatter. Test the two task-cache journeys documented in [the portal test README](../../../Tests/SchoolPortalSync/README.md).

## Change History

### 2026-11-22 — Codex · localized-device-assignment-list
Provide the display locale for the bilingual assignment and notification flow.
