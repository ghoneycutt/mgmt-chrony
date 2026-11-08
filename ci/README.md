# ci

Repeatable tests for this module, to run while working on the code. mgmt has
no module test framework; these scripts do what upstream does for its own
modules and tests: compile everything with `mgmt check`, then apply it on a
real machine and compare the result with fixtures.

Both scripts test this working tree, uncommitted changes included, and resolve
the import `https://github.com/ghoneycutt/mgmt-chrony/` to it. How depends on
`MGMT_MODULE_PATH`:

- set: used as is. It must already contain `github.com/ghoneycutt/mgmt-chrony/`
  as this working tree, for example a checkout or mount at that location.
  Nothing is copied.
- unset: a temporary module path is built from a copy of the working tree and
  removed afterwards.

## fixtures/

- `deploy-defaults.mcl`, `deploy-params.mcl`, `deploy-server.mcl`: the
  deploys the tests apply. The defaults, an include that sets module options
  and every kind of directive, and a server that allows localhost.
- `chrony.conf-<release>`: the file the module must render for
  `deploy-defaults.mcl` on that release, byte-exact, header included.
- `chrony.conf-<release>-params`, `chrony.conf-<release>-server`: the same
  for the other two deploys.

- `defaults/chrony.conf-<release>`: the stock file exactly as shipped by that
  release's chrony package, comments included. The source of truth for the
  module's per release data; see `defaults/README.md` for provenance.

`<release>` is `<ID>-<VERSION_ID>` from `/etc/os-release`, for example
`fedora-44`. The files in `fixtures/` proper are this module's expected
output; only `fixtures/defaults/` holds distribution files.

## check.sh: does it compile?

```sh
ci/check.sh
```

No root. Runs `mgmt check` over both deploy fixtures and every file in
`examples/`. This catches type errors and broken imports but not a wrong
directive name in the template, which is only text to mgmt, nor a misspelled
parameter, which mgmt 1.1.0 silently ignores. Then, for every release in
`fixtures/defaults/`, checks that the module's expected default output has
exactly the stock file's directives, order aside: the module writes them in
the manual's order and the distribution in its own. A text comparison that
needs no machine of that release.

## functional.sh: does it configure a machine correctly?

```sh
sudo ci/functional.sh
```

Root, a release that has fixtures, a machine you do not mind reconfiguring: it
rewrites `/etc/chrony.conf` and restarts chronyd. A throwaway virtual machine
is the intended target. It uses etcd ports 12379/12380 so an mgmt already
running on the machine is not disturbed. In order:

1. applies `deploy-params.mcl` with `mgmt run --converged-exit` and diffs
   `/etc/chrony.conf` against `chrony.conf-<release>-params`;
2. applies `deploy-server.mcl`, diffs against `chrony.conf-<release>-server`,
   and sends an NTP query to 127.0.0.1 with `chronyd -Q`, which must be
   answered: the server side works;
3. applies `deploy-defaults.mcl`, diffs against `chrony.conf-<release>`, and
   repeats the query, which must now be refused: no `allow`, no serving;
4. extracts the stock `chrony.conf` from this release's chrony rpm and checks
   that `fixtures/defaults/chrony.conf-<release>` is byte-identical to it, and
   that the rendered defaults have exactly its directives, order aside. This
   is the guarantee that the module's defaults are the vanilla distribution
   config, and step 3 leaves the machine in that state;
5. checks that `chronyc sources` answers.

Each case also checks that chronyd is active after the apply. A case that
does not converge within 60 seconds almost always means chronyd rejected the
rendered file and the service resource is retrying; the script prints the
mgmt log tail and the last chronyd journal lines.

## Adding a release

1. On a machine of that release, extract the stock file from the chrony
   package (see `fixtures/defaults/README.md`) and store it unchanged as
   `fixtures/defaults/chrony.conf-<release>`; record the package there.
2. Add the `<ID>-<VERSION_ID>` entry to `$platforms` in `main.mcl` from that
   file.
3. Add `fixtures/chrony.conf-<release>`, `-params` and `-server`.
   `ci/check.sh` now verifies the first against the stock file.
4. Run `sudo ci/functional.sh` on that release.
5. Add the release to the tested list in `README.md`.
