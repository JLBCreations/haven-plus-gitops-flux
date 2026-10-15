# Vanilla — Reference Cluster Overlay

> `vanilla` is a reference cluster overlay: it shows what the `infrastructure` and `tenants` Flux Kustomizations look like for a generic, non-local cluster. It has no `flux-system/` directory, so it is never bootstrapped by Flux on its own — use it as the template when adding a new real cluster.

## Strict substitution in Flux

Turn on the `StrictPostBuildSubstitutions` feature gate in kustomize-controller. Then a Kustomization with `postBuild` fails when it meets a `${VAR}` that no variable source supplies. Without the feature gate, Flux replaces the variable with an empty string and shows no error.

The feature gate has these effects:

- The Kustomization stops with the error `variable not set (strict mode)`. Flux applies no object from that Kustomization.
- The objects that are on the cluster stay as they are. Flux does not delete them.
- Kustomizations that depend on the failed Kustomization wait.
- The feature gate applies to all Kustomizations of this Flux installation. A Kustomization without `postBuild` does not change.

The feature gate does not catch a variable with a default, for example `${VAR:=default}`. Flux uses the default.

To turn it on, add `--feature-gates=StrictPostBuildSubstitutions=true` to the kustomize-controller args. With `flux bootstrap`, use a patch in `clusters/<cluster>/flux-system/kustomization.yaml`, as in `clusters/local`. With the Flux Operator, use `spec.kustomize.patches` in the `FluxInstance`.
