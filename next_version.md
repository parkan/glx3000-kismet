# future optimizations

- switch `-j1 V=s` to `-j$(NPROC)` once CI is green
- cache `feeds/` in CI via `actions/cache`
- native ARM build on AWS Graviton t4g.small (no cross-compilation)
- local bare git mirrors for feed repos (offline/fast rebuilds)
- `files/` overlay directory for baking kismet.conf into image
