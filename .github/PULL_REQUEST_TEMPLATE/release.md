## Release

- Version: `YYYY.MM.MICRO`
- Tag: `vYYYY.MM.MICRO`

## Checklist

- [ ] `SCRIPT_VERSION` in `install.sh` matches the release version
- [ ] `CHANGELOG.md` has an entry for this version
- [ ] `mise run check`
- [ ] `./install.sh --version`
- [ ] Install smoke test completed
- [ ] Tag created after merge and pushed
