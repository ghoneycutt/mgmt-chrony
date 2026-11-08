# Stock distribution configs

Pristine `chrony.conf` files exactly as shipped by each release's chrony
package, byte for byte, comments included. They are extracted from the package
itself, never copied from a configured machine:

```sh
dnf download chrony
rpm2cpio chrony-*.rpm | cpio -idm ./etc/chrony.conf
```

They are the source of truth for the module's per release defaults in
`main.mcl`. `ci/check.sh` verifies that the module's expected default output
(`../chrony.conf-<release>`) has exactly the directives of the stock file, and
`ci/functional.sh` verifies that the stored stock file is still identical to
the one in the installed package.

| File | Package |
|---|---|
| `chrony.conf-fedora-44` | chrony-4.9-1.fc44 |
