# SFDX Telecom

This repository contains Salesforce metadata for a telecom project (ATS Telecom). The committed source is limited to `force-app/main/default/`.

## Contents

- `force-app/main/default/` - Salesforce metadata (custom metadata types, objects, etc.)

## Deployment

Use Salesforce CLI (sf) to deploy the metadata:

```bash
sf project deploy start --source-dir force-app/main/default
```

## Notes

This repo was initialized to track only the `force-app/main/default` directory as requested.