# AGENTS.md

Guidance for AI agents (and new contributors) working on this mgmt module.

## What this is

An [mgmt](https://mgmtconfig.com/) module, written in mcl, that configures
chrony. It is consumed with
`import "https://github.com/ghoneycutt/mgmt-chrony/"` and exposes one class,
`chrony.client($st)`, taking one struct: optional module options at the top
level (`package`, `package_state`, `config_file`, `config_file_owner`,
`config_file_group`, `config_file_mode`, `service`, `service_state`,
`service_startup`, `retry`, `delay`) and a required
`config_options` struct with one optional field per directive of the chrony
4.9 chrony.conf(5) manual, named identically, plus a `custom` map for
anything else.

## Toolchain rules

- Target the mgmt 1.1.0 release. It uses `||` as the default operator;
  upstream master renamed it to `<|>` on 2026-08-15 and removed `||`, and no
  release contains that change yet. Do not switch spellings until the module
  targets a release that has `<|>`; the two are mutually exclusive.
- Use `https://` in import URLs, never `git://`. mgmt passes the URL to go-git
  unchanged and GitHub stopped serving the git daemon protocol in 2022.
- There is no module test framework in mgmt. Testing is `mgmt check` for
  compile errors plus applying the module on a real machine; see `ci/`.
- `mgmt fmt` and the format check in `mgmt check` exist only on master. Format
  by hand: tabs for indentation, as the in-tree upstream modules do.

## Commands

```sh
ci/check.sh                 # compile check: no root, any machine with mgmt
sudo ci/functional.sh       # apply and verify: root, a Fedora 44 VM you can reconfigure
```

Both resolve the import to this working tree. Set `MGMT_MODULE_PATH` to a
module path that already contains `github.com/ghoneycutt/mgmt-chrony/` to use
it as is; otherwise a temporary module path is built from a copy of the
working tree. See `ci/README.md`.

To run the module by hand, write a deploy directory with an empty
`metadata.yaml` and a `main.mcl` that imports and includes the class, then:

```sh
mkdir -p /tmp/modules
sudo mgmt run --tmp-prefix lang --module-path /tmp/modules/ --download <deploy dir>/
```

## Conventions

- **`$platforms` holds vanilla distribution defaults only**, keyed by
  `<ID>-<VERSION_ID>` from `/etc/os-release`: what a fresh install of that
  release ships in its chrony.conf, taken from the real distribution package
  named in the entry's comment, never typed from memory or copied from a
  configured machine. The stock file itself is stored unchanged in
  `ci/fixtures/defaults/chrony.conf-<release>`; `ci/check.sh` verifies the
  module's default output against it and `ci/functional.sh` verifies it
  against the installed package.
- **Entries are permanent.** A release leaving support keeps its data; remove
  it from the tested list in `README.md` and `ci/functional.sh` instead.
- **The module has no side effects.** `main.mcl` defines variables and
  classes only; resources live inside `class client`. Anything at the top
  level would be applied by every importer.
- **`examples/` is written as a consumer would write it**, importing by
  repository URL, as upstream's `modules/fwupd/examples/` does. No relative
  imports or symlinks to reach the module from inside its own repo.
- **Two kinds of fields, kept apart.** Module options (what resources the
  module manages and how) are top-level fields of `$st`, named
  `<resource>` for the name and `<resource>_<param>` for a parameter, with
  mgmt's own values (`package_state => "newest"`, `service_state =>
  "stopped"`). The file resource has the static name `chrony_config` and
  takes its path from `config_file`, so consumers can refer to
  `File["chrony_config"]`. chrony.conf directives live under
  `$st->config_options`. `config_options` is required
  because mgmt 1.1.0 cannot default a nested struct (see Gotchas); every
  field inside it is optional.
- **One field per chrony.conf(5) directive, same name, three shapes.**
  A directive the manual allows more than once is `[]str`, one line per
  element holding its arguments; one allowed once is `str`, its arguments,
  `""` omitting it; one without arguments is `bool`. The manual's synopsis
  decides the shape; the module does not interpret the arguments. Anything
  not in the 4.9 manual is for the consumer's `custom` map, not a new field.
  The one naming exception is `includes` for the `include` directive, since
  `include` is a reserved word in mcl (the others are `and as bool class
  collect else float for forkv func if import in int map not or panic str
  struct variant`; check a new directive's name against that list).
- **Directives appear in the manual's order, by section**, in three places
  that must stay in step: the parameter bindings in `main.mcl`, the `$tmpl`
  struct, and `files/chrony.conf.tmpl`, plus the reference table in
  `README.md`. `custom` renders after them, `confdir` and `include` last.
  When a new chrony release adds a directive, add it in all four places.
- **Each `$platforms` entry has the shape of the class parameter**: module
  options at the top level and, under `config_options`, every directive of
  the manual in its order, with the stock value where that release's file
  sets it and the empty value (`[]`, `""`, `false`) where it does not. All
  entries therefore have the same type, and every directive in the class
  resolves the same way:
  `$x type = $st->config_options->x || $platform->config_options->x`,
  always with an explicit type on the binding. Adding a release is adding a
  full row; adding a directive is adding a line to every row, the class, the
  `$tmpl` struct, the template and the README table.
- **One contiguous block per release, nothing shared.** A new platform is
  one new block, its fixtures and a README line, touching no existing row,
  so contributions for different platforms do not conflict. Do not
  introduce per-directive tables (a platform would be scattered over
  dozens of maps) or family-level inheritance between releases (what a
  release gets would depend on another entry). Every release states all of
  its values itself, even when identical to a sibling's.
- **ASCII only.** No em dashes, smart quotes, or other non-ASCII characters.
- Pull requests are typically a single commit; amend rather than stacking
  fixup commits. Preserve original authorship when rebasing contributor
  commits and add co-authors via `Co-Authored-By` trailers.
- Nothing in this repo refers to a contributor's machine: no home directory
  paths, hostnames, or local VM names. Local notes go in `LOCAL.md`, which is
  gitignored.

## Gotchas

- **The module path directory must be named `modules/`.** mgmt rebases the
  module path into the deploy by dropping its last path component and
  assuming the remainder is `/modules/`. Any other name compiles, then fails
  at run time with `metadata.yaml does not exist` under `/modules/`.
- **Type annotations are one line.** The 1.1.0 parser rejects a newline
  inside a type (`struct{` ... `}`), and there is no line continuation and
  no type alias, so the row type in `main.mcl` is a single long line, and
  it appears twice: on the `$platforms` map (so that `[]` in a row has an
  element type) and on `$platform` (without it the nested
  `$platform->config_options` lookup is ambiguous at the module's size,
  although the same pattern unifies in a small program). Both lines change
  only when a directive is added or renamed, never when a platform is
  added, so platform PRs do not touch them.
- **An empty list literal is ambiguous.** `pools => []` in the struct fails
  type unification with `list() is ambiguous`. Bind `$no_pools []str = []`
  first and pass the variable. `ci/lib.sh` does this.
- **A nested struct field cannot be optional.** `$st->config_options ||
  struct{}` fails to unify as soon as the consumer passes a non-empty struct
  (field count differs), and both an omitted `config_options` and an inline
  `config_options => struct{}` fail as ambiguous. What works: the consumer
  always passes `config_options`, and for the defaults passes a typed empty
  variable, `$defaults struct{} = struct{}`. Chained lookups with a default,
  `$st->config_options->x || d`, then type-check for any set of fields.
- **Never pass the same variable in two fields of the class struct.**
  `include chrony.client(struct{pool => $none, sourcedir => $none})` makes
  the mgmt 1.1.0 function engine stall: it logs "function engine
  starting..." and nothing more, then reports convergence without having
  built a graph or run a resource. Reproduced without this module with a
  two-field class and a plain string variable. Two variables or two
  literals work. Consumers and fixtures use one variable per field.
- **Unknown struct fields are silently ignored.** The class parameter's type
  is inferred from the argument, so a misspelled field is not an error.
  There is no way to reject it on 1.1.0; document it, do not claim otherwise.
- **`--download` never updates.** It clones imports missing from the module
  path and leaves existing clones alone; `--update` did not pull in testing.
  Delete the clone to pick up new commits.
- **`mgmt run` does not watch source files.** Code changes need a new deploy:
  restart, or push one into the running instance with
  `mgmt deploy --no-git --seeds http://127.0.0.1:2379 lang ...`.
- **Pass a deploy as a directory**, not as its `main.mcl`; a bare file input
  synthesizes a metadata file and drops `files/`.
- **A config chronyd rejects never converges.** The service resource
  retries forever by default (`retry => -1`), so a bad directive, or an
  `include` pattern whose directory does not exist ("Could not search for
  files matching"), shows up as `mgmt run` never exiting with
  `svc[chronyd]: the CheckApply delay expired!` repeating. Check
  `journalctl -u chronyd`.
- **`--tmp-prefix` leaks.** Every run leaves its state directory, etcd data
  included, 60-120 MB, under /tmp, which is often a tmpfs. When it fills,
  etcd panics with `failed to create WAL: no space left on device`, and
  shortly before that mgmt converges on an empty graph without running any
  resource while reporting success. `ci/functional.sh` uses `--prefix`
  inside its temp directory for that reason. If a run reports convergence
  but changed nothing, check `df /tmp` and remove old `/tmp/mgmt-*` dirs
  that no running mgmt uses.
