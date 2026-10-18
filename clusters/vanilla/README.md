# Vanilla — Reference Cluster Overlay

> `vanilla` is a reference cluster overlay: it shows what the `infrastructure` and `tenants` Flux Kustomizations look like for a generic, non-local cluster. It has no `flux-system/` directory, so it is never bootstrapped by Flux on its own — use it as the template when adding a new real cluster.

## Domain

The vanilla overlays use `${domain}` for each hostname, for example `keycloak.${domain}`. Flux replaces `${domain}` with the value from the `cluster-vars` ConfigMap. Each component Kustomization gets `postBuild.substituteFrom` through a patch in `infrastructure/kustomization.yaml`.

Before the first reconcile, do these steps:

1. Copy `docs/cluster-vars.example.yaml`.
2. Set `domain` to the base domain of the cluster.
3. Apply the ConfigMap to the `flux-system` namespace.
4. Make a wildcard DNS record `*.<domain>` that points to the IP address of the public gateway.

If the ConfigMap does not exist, each Kustomization stops with a "ConfigMap not found" error.

### Runtime variables

Some values are for the container at runtime, for example `${S3_ACCESS_KEY_ID}` in loki and mimir. Flux must not replace them. Use one of these methods:

- Write the variable as `$${S3_ACCESS_KEY_ID}`. Flux removes one `$` and keeps the variable.
- Set the annotation `kustomize.toolkit.fluxcd.io/substitute: disabled` on the object. Flux does not substitute any value in that object. Loki and mimir use this method.

Do not write a default for a runtime variable, for example `${S3_ACCESS_KEY_ID:=x}`. Flux uses the default, also in strict mode, and does not show an error.

Do not use `${domain}` in an object with substitution disabled. Flux does not replace it there.

The CI job `substitutions` runs `scripts/check-substitutions.sh`. The script fails in these conditions:

- A Kustomization renders a variable that `cluster-vars` does not supply.
- A Kustomization renders a variable with a default, and `cluster-vars` does not supply that variable.
- An object with substitution disabled uses a variable from `cluster-vars`.

Also turn on strict substitution in Flux. Then Flux stops with an error on a variable that it cannot replace. See [Strict substitution in Flux](#strict-substitution-in-flux).

## Strict substitution in Flux

Turn on the `StrictPostBuildSubstitutions` feature gate in kustomize-controller. Then a Kustomization with `postBuild` fails when it meets a `${VAR}` that no variable source supplies. Without the feature gate, Flux replaces the variable with an empty string and shows no error.

The feature gate has these effects:

- The Kustomization stops with the error `variable not set (strict mode)`. Flux applies no object from that Kustomization.
- The objects that are on the cluster stay as they are. Flux does not delete them.
- Kustomizations that depend on the failed Kustomization wait.
- The feature gate applies to all Kustomizations of this Flux installation. A Kustomization without `postBuild` does not change.

The feature gate does not catch a variable with a default, for example `${VAR:=default}`. Flux uses the default.

To turn it on, add `--feature-gates=StrictPostBuildSubstitutions=true` to the kustomize-controller args. With `flux bootstrap`, use a patch in `clusters/<cluster>/flux-system/kustomization.yaml`, as in `clusters/local`. With the Flux Operator, use `spec.kustomize.patches` in the `FluxInstance`.
