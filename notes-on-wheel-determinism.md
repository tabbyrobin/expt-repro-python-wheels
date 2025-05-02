# Towards deterministic and reproducible Python wheels: notes and considerations

It would be nice for Python wheels in general to be normalized for
determinism/reproducibility -- in particular, if there were widespread
verifiably bit-for-bit reproducible builds of PyPI-hosted wheels.

I think this topic is probably worth starting a discussion among various
projects about what ideal behavior around reproducibility, if any, "ought to"
look like for Python wheels -- including for `.whl` ZIP metadata, which poses a
particular problem for reproducibility. These notes are intended to help
contribute to that kind of discussion.

There are some caveats and questions of scope to note right away:

* Of course, reproducibly building Python *packages* is already done in a
  widespread way, for example by various Linux distributions. But as of now
  (2025-04), wheels in the general upstream Python ecosystem (e.g. hosted on
  PyPI) are generally not reproducible. (And, most reproducible builds for
  Python packages do not even use the wheel format.)

* If desiring to implement reproducible wheel builds for a specific project, one
  can just pick a strategy, stick with it, and be done with it. But if aiming to
  implement a blanket solution in centralized tools, or blanket
  recommendations/best practices, it's worth investigating the details.

* These notes are about deterministic Python wheels in general. They were
  written based on general background research, but also with reference to
  several concrete projects, in particular cibuildwheel and PyCA `cryptography`.

* These notes are, for the moment, focused on Linux wheels. There is not much in
  here specific to Mac OS or Windows wheels, although many considerations will
  be common to all platforms.

The main goal is to contribute to deciding an appropriate course of action for
recommending best practices and/or implementing defaults in centralized tools
affecting many projects.

These notes do not contain much in the way of conclusions -- they mostly just
generate further questions.

*Disclaimer: These notes are not guaranteed to be comprehensive, or even
systematic. This document is being released as a working draft.*

## From source to wheel

To arrive at a reproducible wheel, there is a whole chain of steps that (in
theory) should be reproducible, including:

- Reproducibility of the underlying artifacts. (For example, compiled extensions
  from C, Rust, etc. This topic will be *mostly out of scope* for these notes.)
- Reproducibility of the sdist `.tar.gz` tarball file, *if the wheel is built
  from sdist* -- including metadata... (These notes focus on wheels, but
  reproducibility of sdists in their own right is important too; and many of the
  issues are similar.)
- Reproducibility of the wheel `.whl` ZIP file -- including metadata:
  Timestamps, file permissions and ownership, ordering of entries, etc.

I say "in theory" because in practice, some types of variation in the inputs may
never make it into the actual wheel.

TODO: add section about other metadata, e.g. group bits (by default git uses
system umask).

## Existing tooling

### General tooling

First mention is cibuildwheel, because the creation and increasingly widespread
adoption of cibuildwheel is a significant step toward making wheel builds
reproducible in a generalized way. That said, cibuildwheel does not address all
aspects of reproducibility; nor is cibuildwheel used by (or necessarily
appropriate for) all projects.

For a description of cibuildwheel's current behavior for ZIP timestamps, and
`SOURCE_DATE_EPOCH` and auditwheel, see:
https://github.com/pypa/cibuildwheel/issues/2344

Also, various projects in the ecosystem are increasingly implementing
reproducibility, for example Hatch,
[setuptools](https://github.com/pypa/setuptools/issues/2133), and auditwheel.
Often, though, the efforts toward reproducibility are spot-fixes and are not
based on a comprehensive assessment of the landscape; so there is still a ways
to go.

### Normalizing ZIP metadata via post-processing

There are a number of tools for this.

To my knowledge, Debian's
[`strip-nondeterminism`](https://salsa.debian.org/reproducible-builds/strip-nondeterminism)
is the most mature and featureful one.

Also of particular interest is
[`python-stripzip`](https://github.com/Code0x58/python-stripzip).

Other tools include:

- https://github.com/keszybz/add-determinism
- https://github.com/KittyHawkCorp/stripzip

There are some issues which arise, notably:

- Ordering of ZIP entries.
- What timestamp(s) *should* be used in the ZIP metadata.
- Whether to respect `SOURCE_DATE_EPOCH` for this usage.

`python-stripzip` does less modifications than `strip-nondeterminism`. In
particular, it doesn't change order of entries, so if `.dist-info` files are
placed at end of the ZIP -- as is best practice -- it will leave them so.

## Considerations and open questions

### Ordering of ZIP entries

Best practice for Python wheels is to put .dist-info at end of archive:

> Place .dist-info at the end of the archive. Archivers are encouraged to place
> the .dist-info files physically at the end of the archive. This enables some
> potentially interesting ZIP tricks including the ability to amend the metadata
> without rewriting the entire archive.
>
> https://packaging.python.org/en/latest/specifications/binary-distribution-format/#recommended-archiver-feature

Debian's strip-nondeterminism orders the entries deterministically, but does NOT
take care to place .dist-info files at end of archive. If using Debian's tool,
this could potentially by solved by patching Debian's tool, or by a custom
script which runs as a step immediately *after* Debian's tool.

Another alternative is to skip Debian's tool entirely, and rely on underlying
tools to guarantee deterministic ordering of entries. Both
[`wheel`](https://github.com/pypa/wheel/issues/183) and
[`pip`](https://github.com/pypa/pip/pull/4667) reportedly do this for recent
versions. With this approach, a simpler tool like `python-stripzip`, which
modifies timestamps and some other metadata, but does not reorder entries, could
be used.

From the handful of experiments I've run, ordering of ZIP entries generally
seems to already be effectively deterministic by default. However, I'm not sure
what nondeterminism might exist depending on OS, OS variants, Python build
backends, etc.

### What timestamp(s) *should* be used in the ZIP metadata

As soon as we start talking about normalizing ZIP timestamps -- particularly if
we talk about a hardcoded default, like setting the fields to zero -- we start
to get into questions of what the whl ZIP timestamps actually *mean*, and what
they are concretely used for.

As far as I can tell, there are no existing conventions around this for Python
wheels.

> "An open question is whether wheel should record timestamps at all, or use the
> earliest possible one."
>
> https://github.com/pypa/wheel/issues/418#issuecomment-911365259

TODO: Survey various existing Python tooling and see if tools read wheel ZIP
timestamps (and other metadata) and how they use them.

#### Blanket reset vs clamping to a max

strip-nondeterminism can wipe out all timestamps to zero, or can set them all to
a given value, or with `--clamp-timestamps` option, can change only those which
are later than a given value (clamp to a max).

It is not clear to me what is most appropriate for potential default behavior
for centralized tools producing (or post-processing) wheels.

A clamping approach is less aggressive and would avoid messing with packages
which somehow may have their own preferences about timestamps. On the other
hand, the more aggressive approach produces potentially greater reproducibility,
by further normalizing data that is generally not meaningful.

#### Choosing the timestamp value for a hardcoded fallback

Various tools seem to set their own hardcoded fallback values. The choice is
sometimes seemingly arbitrary. It would be good to avoid to proliferating the
different defaults. This probably involves discussing with various other
projects before picking a default.

- For example, strip-nondeterminism uses
  [315576060](https://salsa.debian.org/reproducible-builds/strip-nondeterminism/-/blob/master/lib/File/StripNondeterminism/handlers/zip.pm?ref_type=heads#L39),
  which is intended to avoid any timezone mishaps.

- Hatch/hatchling has its own fallback:
  [1580601600](https://hatch.pypa.io/1.13/plugins/utilities/#hatchling.builders.utils.get_reproducible_timestamp)

- python-stripzip zeroes out the fields -- [it sets `last_mod_time` to 0 and
  `last_mod_date` to
  0x21](https://github.com/Code0x58/python-stripzip/blob/38b91d3db01c8298941661b260b3d3b3faf1c756/stripzip.py#L89).
  -- which likely becomes unix epoch time 315532800 (1980-01-01 00:00:00)

### Whether to respect `SOURCE_DATE_EPOCH` for this usage

One thing that is always very relevant for reproducible builds is the
[`SOURCE_DATE_EPOCH`](https://reproducible-builds.org/docs/source-date-epoch/)
environment variable.

This variable is incredibly useful, and can already be used to good effect to
create reproducible ZIP timestamps: for example, if it's set, auditwheel will
take advantage of it and apply it to ZIP timestamps. (And because cibuildwheel
-- for Linux wheels -- invokes auditwheel by default, cibuildwheel also benefits
from this.)

I haven't tested delocate (for MacOS) or delvewheel (for Windows). TODO: test
delocate and delvewheel.

However, `SOURCE_DATE_EPOCH` is not a panacea and presents a few problems when
dealing with ZIP timestamps:

* Setting `SOURCE_DATE_EPOCH` is a relatively heavy-handed way to increase
  reproducibility: it affects more than just the ZIP timestamps. (It is carried
  throughout the env stack and may override timestamps in compiled extensions,
  for example.)

* Commonly suggested ways to set `SOURCE_DATE_EPOCH` include taking the date
  from a changelog file, or from a git commit timestamp. However, there seems to
  be a move to recommend best practice to build wheels from sdists, that is,
  [source->sdist->wheel](https://discuss.python.org/t/should-building-wheels-from-sdists-be-recommended-behavior/8358)
  (and not directly from VCS checkout etc). See also
  https://github.com/pypa/build/issues/311, "Implement building wheels from
  sdist/tarball artifacts". In this context, VCS metadata like a git timestamp
  *doesn't actually exist in the sdist*.

* Minor point: `SOURCE_DATE_EPOCH` uses unix epoch time, but ZIPs use DOS
  timestamps, and unix epoch time zero is not the same as DOS epoch time zero.
  However, one can simply clamp `SOURCE_DATE_EPOCH` forwards if it's prior to
  the DOS timestamp epoch. That said, failing to do so can cause
  [problems](https://github.com/pypa/auditwheel/issues/566).

#### Kludgy workaround for the sdist-lacks-VCS-metadata problem: `__source-date-epoch.txt`

Yocto project outlines how they go about determining a `SOURCE_DATE_EPOCH`
value:

> 1. Use value from `__source-date-epoch.txt` file if this file exists. This
>    file was most likely created in the previous build by one of the following
>    methods 2,3,4. (But, in principle, it could actually provided by a recipe
>    via SRC_URI)
>
> If the file does not exist:
>
> 2. Use .git last commit date timestamp (git does not allow checking out files
>    and preserving their timestamps)
>
> 3. Use "known" files such as NEWS, CHANGLELOG, ...
>
> 4. Use the youngest file of the source tree.

> https://wiki.yoctoproject.org/wiki/Reproducible_Builds#Current_Development

A Yocto-inspired approach can be applied to sdists/wheels. At sdist generation
time, the VCS timestamp can be retrieved and written to e.g.
`__source-date-epoch.txt`, which becomes something of an ephemeral, but
crystallized, artifact: it is present in the sdist, but was not in the VCS
source code, and will not be a file in the wheel either.

While I'm not convinced this is an advisable approach, even for an individual
project, nevertheless, here is an example of implementing it:
https://github.com/tabbyrobin/py-sigsum-tools-wrapper/blob/5dbb7bfec3770dc917d8b63b5337200d2445da4b/noxfile.py#L112-L167

This approach may be appropriate for individual projects, if they choose to
arrange their build system that way. But it is somewhat kludgy, and does not
seem scalable as a generalized, on-by-default solution. That said, it *might*
make sense for various tools to opportunistically take advantage of
`<sdist>/__source-date-epoch.txt`, if present, much as they opportunistically
use `SOURCE_DATE_EPOCH` now.

That said, ZIP metadata timestamps might be considered more akin to filesystem
timestamps, and not really the same kind of situation as `SOURCE_DATE_EPOCH`.
Yocto project has a separate variable for image FS timestamps:

> `REPRODUCIBLE_TIMESTAMP_ROOTFS`. When building packages, various timestamps
> can be controlled by SOURCE_DATE_EPOCH. This, however, does not work for
> building images. Images contain various scattered timestamps, and as a
> consequence, two builds of otherwise identical images will differ. The purpose
> of this variable is to use the value as a "catch-all" rootfs image timestamp
> and build all images with identical timestamps. The value for this variable is
> always up to the developers/image builders.

## Other notes

_These notes are in no particular order._

Here is a script using cibuildwheel and python-stripzip which demonstrates
successfully generating bit-for-bit reproducible wheels for a straightforward
Cython project:
https://gist.github.com/tabbyrobin/d6c5cf5323fe54a50004c1291da39315#file-build-wheels-sh

At one point, Rubygems decided to
[set](https://github.com/rubygems/rubygems/issues/2290) `SOURCE_DATE_EPOCH` env
var (if unset) , and then later realized that this created
[problems](https://github.com/rubygems/rubygems/issues/3081) for other code, and
modified their approach to be less invasive.

Reproducibility-focused distro StageX obviates the wheel metadata problem
entirely by
[mock-installing](https://codeberg.org/stagex/stagex/src/commit/24e6ac30a4a9d3436619be653385269e21bd47fb/packages/py-cryptography/Containerfile#L41)
the wheel, and copying the resulting files. I think distro packaging (APT,
DNF...) generally works in similar way. That is, they don't use the wheel format
(except ephemerally during package preparation), instead, they deal directly
with the included files.

cibuildwheel includes `CIBW_REPAIR_WHEEL_COMMAND` var which could be a handy
entrypoint for normalizing whl ZIPs, but it's not quite right for this usage.

The `uv build` command (as of uv version 0.6.14) introduces additional
nondeterminism into the build environment due to its use of random temp paths.
These random paths can end up inside of resulting binaries -- for example, this
is the case with PyCA cryptography. Some of the PyPI-hosted wheels of PyCA
cryptography (e.g. version 44.0.2) include these random paths (in the rust
`.so`). See: https://github.com/astral-sh/uv/issues/13096

An Airflow developer pointed out:

> "Another example is enabling reproducible builds - while many backends have a
> way to produce reproducible builds, one of the ways how to do it is to pass an
> environment variable to set the "date" with which files will be stored in
> .whl, but you also should do some other stuff before you run the build - for
> example make sure that group bits are cleared on all source files, because by
> default git uses system umask and it might impact reproducibility.
>
> Those behaviours (and likely a number of others) are not entirely covered by
> PEP 517 - possibly some of those will be in the future by follow-up PEPs - but
> in order to make a good user experience, some custom ways of interaction
> between frontend and backend have to be implemented."
>
> https://github.com/astral-sh/uv/issues/3957#issuecomment-2658950111

For an example of build reproducibility implemented for Airflow, see:
https://github.com/apache/airflow/blob/main/reproducible_build.yaml

From [PEP 725](https://peps.python.org/pep-0725/) - "Specifying external
dependencies in pyproject.toml":

> Differences between sdist and wheel metadata
>
> A wheel may vendor its external dependencies. This happens in particular when
> distributing wheels on PyPI or other Python package indexes - and tools like
> auditwheel, delvewheel and delocate automate this process. As a result, a
> Requires-External entry in an sdist may disappear from a wheel built from that
> sdist. It is also possible that a Requires-External entry remains in a wheel,
> either unchanged or with narrower constraints. auditwheel does not vendor
> certain allow-listed dependencies, such as OpenGL, by default.
>
> https://peps.python.org/pep-0725/#differences-between-sdist-and-wheel-metadata

"Building Python Lambda Functions in CDK with uv", 02 Jan 2025
https://maxfriedrich.de/2025/01/02/uv-lambda-cdk/ -- This does not mention
wheels directly, but it is relevant to other aspects of determinism in Python
deployments.

While it is entirely possible to use `SOURCE_DATE_EPOCH` for ZIP timestamps, and
some important projects already do so, care must be taken when implementing,
because ZIP uses DOS timestamps that start at 1980-01-01, while
`SOURCE_DATE_EPOCH` uses unix epoch time starting at 1970-01-01. Naive
implementations can cause tools to crash; see:
https://github.com/pypa/auditwheel/issues/566 and
https://github.com/pypa/wheel/issues/418

"Asaman" codebase is seemingly unmaintained, but this is a good source of
inspiration/reference, and historically was an important part of getting the
general Python tooling to where it is already (e.g. support for
`SOURCE_DATE_EPOCH`):
https://discuss.python.org/t/introducing-asaman-a-tool-to-bulid-reproducible-wheels/10932/

There is discussion about a "Wheel 2.0" version, scattered around various
places, for example:
https://discuss.python.org/t/speculative-wheel-2-0-and-migration-strategies/21600/
So far I have not noticed any mention of determinism/reproducible builds. It
would be good to have reproducibility baked into any future format from the
start.

In theory, different sdists can convergently generate identical wheels. This
becomes untrue if the sdist hash is included in the wheel. This may be desirable
as provenance/SBOM, and
[`Source-Archive`](https://discuss.python.org/t/provide-a-way-to-signal-an-sdist-isnt-meant-to-be-built/56849/2)
wheel metadata field has been suggested. See also:

> The sdist format is not defined, there is no guarantee the build process is
> deterministic. The build system could touch the files when creating the
> tarball, which would result in different timestamps and then a different hash,
> for example.
>
> https://discuss.python.org/t/draft-pep-recording-the-source-hash-of-installed-distribution/4660/

There is good discussion and details about tooling (for example, flit's default
behavior, etc.) in this forum topic:

> I have come across a few design decisions related to the wheel format which
> the PEP says nothing about but which are important to resolve.
>
> 1. File timestamps: should we store them, or set them to the UNIX epoch
>    (1970-01-01)?
>
> 2. File permissions: should we store them or not? Some users say they need to
>    flag scripts as executable.
>
> 3. Should symbolic links be stored in wheels? A use case was given just now in
>    wheel issue #400. There are open questions around RECORD handling and
>    extraction on Windows.
>
> https://discuss.python.org/t/clarifications-to-the-wheel-specification/8141
