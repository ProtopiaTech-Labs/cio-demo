# Alert rules

Every deploy loads the rule groups in this directory into the shop's Grafana folder
(`deploy/grafana-sync.sh`); groups that are no longer here are deleted.

Format: Grafana's alert-rule file provisioning (Alerting → Export → YAML): `groups[]`
with `name`, `interval` and `rules[]` (`uid`, `title`, `condition`, `data`, `for`,
`labels`, `annotations`, `noDataState`, `execErrState`). `${NAMESPACE}` becomes the
shop's namespace, and each `uid` gets the namespace as a prefix. A rule's alerts go to
a contact point when it sets `notification_settings.receiver`.
