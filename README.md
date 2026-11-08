# mgmt-chrony

#### Table of Contents

1. [Module Description - What the module does and why it is useful](#module-description)
1. [Setup - The basics of getting started with chrony](#setup)
   * [What chrony affects](#what-chrony-affects)
   * [Setup requirements](#setup-requirements)
   * [Beginning with chrony](#beginning-with-chrony)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Limitations - OS compatibility, etc.](#limitations)
1. [Development - Guide for contributing to the module](#development)

## Module description

This [mgmt](https://mgmtconfig.com/) module manages
[chrony](https://chrony-project.org/), the NTP client and server. It manages
the chrony package, the `chrony.conf` file, the chronyd service, and the
configuration options inside that file. Every directive of
the chrony 4.9
[chrony.conf(5)](https://chrony-project.org/doc/4.9/chrony.conf.html) manual
is available under the same name, and a `custom` map takes anything else, so
chronyd can be configured as a client, a server, or both.

For each supported platform the module carries the default values that the
distribution ships in its `chrony.conf`, taken from the distribution's own
package. A machine therefore continues to run the stock configuration unless
you specify other options, and the options you do specify change only those
directives.

It does not manage anything the configuration may refer to: systemd unit
overrides, key files, NTS certificates and keys, files for `include` and
`confdir`, firewall rules, or the directories a directive points at. Those
possibilities are limitless and cannot be modeled here; manage them
separately in your own deploy, alongside this class.

## Setup

### What chrony affects

* The `chrony` package, installed.
* The chrony configuration file, `/etc/chrony.conf` on Fedora, rewritten from
  a template. Every directive in it comes from the module's per release data
  or from your parameters.
* The `chronyd` service, running and enabled, notified when the file changes.

Nothing else. The package, file and service names default to the running
release's and can be overridden.

### Setup requirements

mgmt 1.1.0 or later releases. The module uses the `||` default operator of the
1.1.0 release; upstream master renamed it to `<|>` in August 2026, so a build
newer than that needs the one line change described under
[Limitations](#limitations).

Modules are imported by repository URL and resolved under a module path, which
`mgmt` is told about with `--module-path`. That directory must be an absolute
path, end with a slash, and have `modules` as its last component. With
`--download`, imports missing from it are cloned on first use.

### Beginning with chrony

Write a deploy: a directory holding a `metadata.yaml`, which may be empty, and
a `main.mcl` that imports the module and includes its class. The class takes
one struct; `config_options` holds the chrony.conf directives and must be
passed, and a typed empty struct means "the defaults" (see
[Usage](#usage) for why).

```mcl
import "https://github.com/ghoneycutt/mgmt-chrony/"

$defaults struct{} = struct{}

include chrony.client(struct{
	config_options => $defaults,
})
```

Run it. The first run clones the module into the module path.

```sh
mkdir -p /tmp/modules
sudo mgmt run --tmp-prefix lang --module-path /tmp/modules/ --download site/
```

On Fedora 44 this writes `/etc/chrony.conf` with the following content: the
directives of the stock file from the `chrony-4.9-1.fc44` package, in the
order the manual lists them.

```
# This file is managed by mgmt. Do not edit.
pool 2.fedora.pool.ntp.org iburst
ntsdumpdir /var/lib/chrony
driftfile /var/lib/chrony/drift
leapseclist /usr/share/zoneinfo/leap-seconds.list
makestep 1.0 3
rtcsync
logdir /var/log/chrony
sourcedir /run/chrony-dhcp
```

## Usage

The class takes one struct with two kinds of fields.

**Module options**, at the top level, all optional:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `package` | `str` | the release's, `chrony` on Fedora | package name |
| `package_state` | `str` | `installed` | `installed`, `uninstalled`, `newest`, or a version string |
| `config_file` | `str` | the release's, `/etc/chrony.conf` on Fedora | path of the file to write |
| `config_file_owner` | `str` | `root` | owner of the file |
| `config_file_group` | `str` | `root` | group of the file |
| `config_file_mode` | `str` | `0644` | mode of the file, octal or symbolic |
| `service` | `str` | the release's, `chronyd` on Fedora | service unit name |
| `service_state` | `str` | `running` | `running` or `stopped` |
| `service_startup` | `str` | `enabled` | `enabled` or `disabled` |
| `retry` | `int` | `-1` | how many times a failed service apply is retried; `-1` means forever |
| `delay` | `int` | `1000` | milliseconds between service retries |

The file resource is named `chrony_config` whatever its path, so other code in
your deploy can depend on `File["chrony_config"]`. The package and service
resources are named after the package and unit, as mgmt requires.

**`config_options`**, a struct holding the chrony.conf directives. Its fields
map 1:1 onto the directives of the chrony 4.9 chrony.conf(5) manual, under
the same names, with a single exception: the `include` directive is the field
`includes`, because `include` is a reserved word in mcl. Every field is
optional and defaults to the stock value for the running release where the
stock file sets that directive, otherwise to nothing. Fields come in three
shapes, following the manual's synopsis of each directive:

* `[]str` for a directive that may appear more than once: one line per
  element, each element being the directive's arguments. An empty list emits
  nothing.
* `str` for a directive that appears at most once: its arguments. An empty
  string omits the directive.
* `bool` for a directive that takes no arguments.

Directives are written in the order the manual lists them, by section, then
`custom`, then `confdir` and `include` last so that included files take
precedence (chrony applies the last occurrence of a directive).

`config_options` itself is required. mgmt 1.1.0 cannot give a nested struct a
default, and an inline `struct{}` is rejected as ambiguous, so to get the
defaults pass a typed empty struct variable, as in the example above.

#### Adding your own servers

```mcl
import "https://github.com/ghoneycutt/mgmt-chrony/"

include chrony.client(struct{
	config_options => struct{
		server => ["time.cloudflare.com iburst", "time.nist.gov iburst"],
	},
})
```

This keeps the distribution pool and adds two servers. Each element is a
complete `server` line without the keyword, so any option the manual allows,
such as `iburst`, `nts` or `maxpoll 10`, goes in the string.

#### Replacing the distribution pool

An empty list literal has no element type, so `pool => []` fails type
unification. Bind a typed variable and pass that. Use a separate variable for
each field: passing the same variable in two fields makes mgmt 1.1.0 report
convergence without ever applying anything (see `AGENTS.md`).

```mcl
import "https://github.com/ghoneycutt/mgmt-chrony/"

$no_pools []str = []

include chrony.client(struct{
	config_options => struct{
		pool => $no_pools,
		server => ["ntp1.example.org iburst", "ntp2.example.org iburst"],
	},
})
```

This would create `/etc/chrony.conf` with the following content.

```
# This file is managed by mgmt. Do not edit.
server ntp1.example.org iburst
server ntp2.example.org iburst
ntsdumpdir /var/lib/chrony
driftfile /var/lib/chrony/drift
leapseclist /usr/share/zoneinfo/leap-seconds.list
makestep 1.0 3
rtcsync
logdir /var/log/chrony
sourcedir /run/chrony-dhcp
```

#### Serving time on a LAN

```mcl
include chrony.client(struct{
	config_options => struct{
		allow => ["192.168.0.0/16", "10.0.0.0/8"],
		local => "stratum 10",
	},
})
```

The server side is covered by the functional test, which applies `allow` and
`local` and verifies that chronyd answers an NTP query, and that it refuses
one with the defaults.

#### Disabling a directive

```mcl
$no_dirs []str = []

include chrony.client(struct{
	config_options => struct{
		sourcedir => $no_dirs,
		rtcsync => false,
		leapseclist => "",
	},
})
```

#### Changing what the module manages

```mcl
include chrony.client(struct{
	package_state => "newest",
	config_file_mode => "0640",
	service_startup => "disabled",
	retry => 5,
	delay => 2000,
	config_options => struct{
		server => ["ntp.example.org iburst"],
	},
})
```

#### Directives the module does not know

`custom` is a map from directive name to argument text, for a directive newer
than chrony 4.9 or one that only a particular distribution's build accepts. An
empty value renders the directive alone. Entries render after the known
directives, sorted by name, and are passed through verbatim, so a directive
chronyd does not understand still stops it from starting.

```mcl
include chrony.client(struct{
	config_options => struct{
		custom => {
			"somenewdirective" => "1 2 3",
			"someflag" => "",
		},
	},
})
```

#### Reference

Every directive of chrony 4.9, by manual section, as fields of
`config_options`. The *Renders* column shows the manual's synopsis; see the
manual for what each argument means.

**Time sources**

| Field | Type | Renders |
|---|---|---|
| `server` | `[]str` | one `server <hostname [option]...>` line per element |
| `pool` | `[]str` | one `pool <name [option]...>` line per element |
| `peer` | `[]str` | one `peer <hostname [option]...>` line per element |
| `initstepslew` | `str` | `initstepslew <step-threshold [hostname]...>` |
| `refclock` | `[]str` | one `refclock <driver parameter[:option]... [option]...>` line per element |
| `manual` | `bool` | `manual` |
| `acquisitionport` | `str` | `acquisitionport <port>` |
| `bindacqaddress` | `[]str` | one `bindacqaddress <address>` line per element |
| `bindacqdevice` | `str` | `bindacqdevice <interface>` |
| `dscp` | `str` | `dscp <point>` |
| `dumpdir` | `str` | `dumpdir <directory>` |
| `maxsamples` | `str` | `maxsamples <samples>` |
| `minsamples` | `str` | `minsamples <samples>` |
| `ntsaeads` | `str` | `ntsaeads <ID...>` |
| `ntsdumpdir` | `str` | `ntsdumpdir <directory>` |
| `ntsrefresh` | `str` | `ntsrefresh <interval>` |
| `ntstrustedcerts` | `[]str` | one `ntstrustedcerts <[set-ID] file|directory>` line per element |
| `nosystemcert` | `bool` | `nosystemcert` |
| `nocerttimecheck` | `str` | `nocerttimecheck <limit>` |
| `refresh` | `str` | `refresh <interval>` |

**Source selection**

| Field | Type | Renders |
|---|---|---|
| `authselectmode` | `str` | `authselectmode <mode>` |
| `combinelimit` | `str` | `combinelimit <limit>` |
| `maxdistance` | `str` | `maxdistance <distance>` |
| `maxjitter` | `str` | `maxjitter <jitter>` |
| `maxstratum` | `str` | `maxstratum <stratum>` |
| `minstratum` | `str` | `minstratum <stratum>` |
| `minsources` | `str` | `minsources <sources>` |
| `reselectdist` | `str` | `reselectdist <distance>` |
| `stratumweight` | `str` | `stratumweight <distance>` |

**System clock**

| Field | Type | Renders |
|---|---|---|
| `clockprecision` | `str` | `clockprecision <precision>` |
| `corrtimeratio` | `str` | `corrtimeratio <ratio>` |
| `driftfile` | `str` | `driftfile <file [interval interval]>` |
| `fallbackdrift` | `str` | `fallbackdrift <min-interval max-interval>` |
| `leapsecmode` | `str` | `leapsecmode <mode>` |
| `leapsectz` | `str` | `leapsectz <timezone>` |
| `leapseclist` | `str` | `leapseclist <file>` |
| `makestep` | `str` | `makestep <threshold limit>` |
| `maxchange` | `str` | `maxchange <offset start ignore>` |
| `maxclockerror` | `str` | `maxclockerror <error-in-ppm>` |
| `maxdrift` | `str` | `maxdrift <drift-in-ppm>` |
| `maxupdateskew` | `str` | `maxupdateskew <skew-in-ppm>` |
| `maxslewrate` | `str` | `maxslewrate <rate-in-ppm>` |

**NTP server**

| Field | Type | Renders |
|---|---|---|
| `allow` | `[]str` | one `allow <[all] [subnet]>` line per element |
| `deny` | `[]str` | one `deny <[all] [subnet]>` line per element |
| `bindaddress` | `[]str` | one `bindaddress <address>` line per element |
| `binddevice` | `str` | `binddevice <interface>` |
| `broadcast` | `[]str` | one `broadcast <interval address [port]>` line per element |
| `clientloglimit` | `str` | `clientloglimit <limit>` |
| `noclientlog` | `bool` | `noclientlog` |
| `local` | `str` | `local <[option]...>` |
| `ntpsigndsocket` | `str` | `ntpsigndsocket <directory>` |
| `ntsport` | `str` | `ntsport <port>` |
| `ntsservercert` | `str` | `ntsservercert <file>` |
| `ntsserverkey` | `str` | `ntsserverkey <file>` |
| `ntsprocesses` | `str` | `ntsprocesses <processes>` |
| `maxntsconnections` | `str` | `maxntsconnections <connections>` |
| `ntsntpserver` | `str` | `ntsntpserver <hostname>` |
| `ntsrotate` | `str` | `ntsrotate <interval>` |
| `port` | `str` | `port <port>` |
| `ratelimit` | `str` | `ratelimit <[option]...>` |
| `ntsratelimit` | `str` | `ntsratelimit <[option]...>` |
| `smoothtime` | `str` | `smoothtime <max-freq max-wander [leaponly]>` |

**Command and monitoring access**

| Field | Type | Renders |
|---|---|---|
| `bindcmdaddress` | `[]str` | one `bindcmdaddress <address>` line per element |
| `bindcmddevice` | `str` | `bindcmddevice <interface>` |
| `cmdallow` | `[]str` | one `cmdallow <[all] [subnet]>` line per element |
| `cmddeny` | `[]str` | one `cmddeny <[all] [subnet]>` line per element |
| `cmdport` | `str` | `cmdport <port>` |
| `cmdratelimit` | `str` | `cmdratelimit <[option]...>` |
| `opencommands` | `str` | `opencommands <[command]...>` |

**Real-time clock (RTC)**

| Field | Type | Renders |
|---|---|---|
| `hwclockfile` | `str` | `hwclockfile <file>` |
| `rtcautotrim` | `str` | `rtcautotrim <threshold>` |
| `rtcdevice` | `str` | `rtcdevice <device>` |
| `rtcfile` | `str` | `rtcfile <file>` |
| `rtconutc` | `bool` | `rtconutc` |
| `rtcsync` | `bool` | `rtcsync` |

**Logging**

| Field | Type | Renders |
|---|---|---|
| `log` | `str` | `log <[option]...>` |
| `logbanner` | `str` | `logbanner <entries>` |
| `logchange` | `str` | `logchange <threshold>` |
| `logdir` | `str` | `logdir <directory>` |
| `mailonchange` | `str` | `mailonchange <email threshold>` |

**Miscellaneous**

| Field | Type | Renders |
|---|---|---|
| `sourcedir` | `[]str` | one `sourcedir <directory...>` line per element |
| `hwtimestamp` | `[]str` | one `hwtimestamp <interface [option]...>` line per element |
| `hwtstimeout` | `str` | `hwtstimeout <timeout>` |
| `maxtxbuffers` | `str` | `maxtxbuffers <messages>` |
| `keyfile` | `str` | `keyfile <file>` |
| `lock_all` | `bool` | `lock_all` |
| `pidfile` | `str` | `pidfile <file>` |
| `ptpport` | `str` | `ptpport <port>` |
| `ptpdomain` | `str` | `ptpdomain <domain>` |
| `sched_priority` | `str` | `sched_priority <priority>` |
| `user` | `str` | `user <user>` |

**Included files**

| Field | Type | Renders |
|---|---|---|
| `confdir` | `[]str` | one `confdir <directory...>` line per element |
| `includes` | `[]str` | one `include <pattern>` line per element (`include` is a reserved word in mcl, hence the field name) |

**Anything else**

| Field | Type | Renders |
|---|---|---|
| `custom` | `map{str: str}` | `<name> <value>` per entry, sorted by name; `<name>` alone when the value is empty |

## Limitations

This module has been tested on the following releases. The stock configuration
for each is stored in `ci/fixtures/defaults/` and verified against the real
distribution package by `ci/functional.sh`.

 * Fedora 44

A release not in the module's data makes the include fail with
`mgmt-chrony: unsupported os release`. Adding one is a single entry in
`main.mcl` plus its fixtures; see `AGENTS.md`.

mgmt 1.1.0 infers the class parameter's type from the struct you pass, so a
misspelled field such as `servers` instead of `server` is silently ignored
rather than rejected. Check the rendered file.

The module renders what you give it and does not validate it. chronyd does,
at start: a bad argument, an unknown directive in `custom`, or an `include`
pattern whose directory does not exist keeps the service from starting, which
mgmt then reports and, with the default `retry` of `-1`, retries forever.

On an mgmt built from upstream master after August 2026, replace every `||`
in `main.mcl` with `<|>`; the two spellings are mutually exclusive and no
release accepts both yet.

## Development

The `ci/` directory holds the tests: `ci/check.sh` compiles every way the
module is used and checks the default output against the stored stock files,
and `sudo ci/functional.sh` applies the module on a Fedora 44 machine as a
client and as a server, diffs the results against fixtures and the stock
package file, and queries the server. The functional test rewrites that
machine's chrony configuration, so run it on a virtual machine you do not
mind reconfiguring. See `ci/README.md` and `AGENTS.md`.

### Adding a new platform

A platform is a distribution release, identified as `<ID>-<VERSION_ID>` from
its `/etc/os-release`, for example `debian-13`. Its data is the configuration
the release ships, taken from the release's own chrony package, never from a
configured machine or from memory. Everything for a release lives in one
block, so adding one touches no existing platform.

1. On a machine of that release, extract the stock `chrony.conf` from the
   chrony package and store it unchanged, comments included, as
   `ci/fixtures/defaults/chrony.conf-<release>`. For an rpm:

   ```sh
   dnf download chrony
   rpm2cpio chrony-*.rpm | cpio -idm ./etc/chrony.conf
   ```

   For a deb, `apt-get download chrony` and `dpkg-deb -x`. Record the package
   version in `ci/fixtures/defaults/README.md`.

2. Add a block for the release to `$platforms` in `main.mcl`, before the
   final `unsupported` row. Copy an existing block: set `package`,
   `config_file` and `service` to the release's names, then under
   `config_options` set every directive the stock file contains to its
   arguments and leave every other directive at its empty value (`[]`, `""`
   or `false`). The block lists all directives in the manual's order; keep
   that order.

3. Add the three expected rendered files, `ci/fixtures/chrony.conf-<release>`,
   `-params` and `-server`: the module's output for `deploy-defaults.mcl`,
   `deploy-params.mcl` and `deploy-server.mcl` on that release, byte for
   byte, header included, directives in the manual's order.

4. Run `ci/check.sh` anywhere. It verifies that the defaults fixture has
   exactly the stock file's directives, so a typo in the block shows up here
   without a machine of that release.

5. Run `sudo ci/functional.sh` on the release. It applies the three deploys,
   diffs the results against your fixtures, proves the stored stock file is
   the one in the installed package, and queries the server.

6. Add the release to the list under [Limitations](#limitations).

Nothing else changes. If the release's stock file uses a directive the
module does not know, that directive belongs in the module first: a new
field in every `$platforms` block, in the class, in the `$tmpl` struct, in
`files/chrony.conf.tmpl` and in the reference table above, all in the
manual's position.
