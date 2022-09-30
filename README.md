# Multi-cluster-monitoring with custom helm

## observer
- With thanos, aggregate observees' metrics.
- With grafana, visualize metrics for observability.

## observee
- With node exporter and prometheus, pull cluster's metrics and respond to thanos query.

## Objstore.yml
- Secret configuration for service account of storage
- Same for observer and observee
```

kubectl create secret generic objstore-secret --from-file=objstore.yml -n {ns} --context={cluster context}

```

## addCluster.sh
- Automatically update/make observer/observee's yaml file when adding new observee cluster.
