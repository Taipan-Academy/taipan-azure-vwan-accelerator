# Workbook source

Repository: https://github.com/Azure/Azure-Network-Security

Commit: `90e98005b1356b6e8ceb90cdb312b6c759fefb49`

Source: Azure Firewall/Workbook - Azure Firewall Monitor Workbook/Azure Firewall_ResourceSpecific_ARM.json

Changes: extract serialized workbook data, preselect the POC workspace and firewall, and default the time range to one hour.

Original template and upstream licence are retained alongside this file.
Workbook panels are inherited from Microsoft; features without generated traffic or enabled capabilities may have no data.

Local enhancement: added Overview POC traffic evidence tables using resource-specific firewall logs without GeoLocation lookups.

Vendored text files use LF line endings with trailing whitespace removed. JSON content is preserved; the reference template is not byte-identical to the upstream file.
