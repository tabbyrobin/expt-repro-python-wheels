> [!NOTE]
> I am not affiliated with PyCA or the `cryptography` project. (And they did not
> ask me to undertake this project, I did it of my own initiative.)

# Towards reproducible wheels for PyCA's `cryptography`

This is a work in progress.

I set out to try to reproduce the official wheel builds for PyCA's
`cryptography` package.

The `cryptography` project, in the large sense, is already built reproducibly by
various downstream projects (for example by several Linux distributions).
However, as of 2025-04, the official upstream wheels, hosted on PyPI, are not
built in a reproducible manner.

When starting out, for all I knew, the wheels may have already been
reproducible. But I figured they were probably not, since the way things are (in
2025) is generally that builds are not reproducible unless specific care has
been taken to make sure they are.

Given that my eventual goal was to hopefully get the changes upstreamed, I
planned to make the most minimal changes possible to the codebase. (Here I use
"codebase" to include the build logic.) This makes for a more challenging
project compared to having free reign to adapt procedures at will, the way that
downstream projects generally do.

I took as a reference point release 44.0.2, since that was the most recent
release when I started.

- https://github.com/pyca/cryptography/tree/44.0.2
- https://pypi.org/project/cryptography/44.0.2/
- https://www.wheelodex.org/projects/cryptography/

Of course, I didn't figure everything out on my own. At various steps I
consulted with various people, particularly on IRC channels and Matrix rooms. I
don't quote names in this writeup (although if anyone who helped would like to
be named, I will), but credit goes to various others who helped me figure out
various problems along the way.

## Background -- what are reproducible builds?

For general background on reproducible builds, see:

- https://reproducible-builds.org/
- https://slsa.dev/spec/v1.0/faq#q-what-about-reproducible-builds
- https://www.bootstrappable.org/
- https://guix.gnu.org/en/blog/2023/the-full-source-bootstrap-building-from-source-all-the-way-down/

Presently, I tried to address the 'reproducible' and 'verifiable' dimensions,
but not the 'bootstrappable' dimension.

## Orientation

My very initial steps were to follow the
[docs](https://cryptography.io/en/latest/installation/#building-cryptography-on-linux),
checkout the repo and try `python -m build`, etc. I successfully built a wheel
or two.

During the early stages, I avoided consulting with PyCA or the `cryptography`
project, because I wanted to know what I was talking about before I talked to
them.

`cryptography` is a non-trivial wheel build, because it depends on compiled
extensions -- and these are not classic/basic Cython extensions. The two main
dependencies are: the project-internal Rust/Maturin code, and openssl (actually,
BoringSSL *or* OpenSSL).

While the docs on building left some things unclear, they were sufficient to get
me started. They were also sufficient to make me aware of the fact that for
`cryptography`, there are several different build scenarios, and I would need to
figure out which one was applicable.

In particular, things are different if you are using just OpenSSL headers (such
as provided by `apt-get install libssl-dev pkg-config`), versus if you want to
compile a particular version of OpenSSL, and if you want to create a
statically-linked wheel (vs a dynamically-linked wheel).

> Cryptography ships statically-linked wheels for macOS, Windows, and Linux (via
> manylinux and musllinux). This allows compatible environments to use the most
> recent OpenSSL, regardless of what is shipped by default on those platforms.
>
> https://cryptography.io/en/latest/installation/#static-wheels

The docs did not mention any details about how the official upstream PyPI-hosted
artifacts are built. I figured out by browsing the source tree and the GH issues
that they are built and deployed using GitHub Actions, and furthermore that
significant build logic is implemented as GitHub Actions YAML.

At this point I realized that I was going to need to figure out how to execute
that YAML in alternative ways, and did some web searches which led me to local
GHA runners.

## Getting the GitHub Actions YAML to run locally

> “Verified reproducible” means using two or more independent build platforms to
> corroborate the provenance of a build. In this way, one can create an overall
> platform that is more trustworthy than any of the individual components. This
> is often suggested as a solution to supply chain integrity.
>
> https://slsa.dev/spec/v1.0/faq#q-what-about-reproducible-builds

It's one thing for a build to be *reproducible*, but for it to be
[*verifiably*](https://slsa.dev/spec/v1.0/faq#q-what-about-reproducible-builds)
so, it needs to be able to be replicated on a variety of hardware, and
preferably a variety of software systems. 'GitHub Actions' is not really
designed for this -- it is generally centered around executing on GH's data
center hardware, and with their specific software stack.

Prior to starting this project, I was not deeply familiar with GitHub Actions,
so there was a fair bit of general background familiarization to do. I did this
simultaneously with jumping into using GHA in an unconventional way (that is:
trying to run them locally).

In terms of software to run GitHub Actions YAML locally ("local runners"), there
are not many options: either [Nektos Act](https://nektosact.com/), or GitHub
official local runners.

I chose Act over the GitHub official local runners because people were generally
talking positively (and more often) about Act. I also had the sneaking suspicion
that the official runners would likely be maladapted to my use case in some way,
because GitHub Actions generally is not designed with this kind of thing as
priority. So I decided to prefer the third-party tool. I later learned that the
official local runner images are quite large (tens of gigabytes, which will not
fit on my laptop with limited disk space), so this suspicion was borne out.

Nektos Act is underdocumented, and it is only partially compatible with GHA.
Some things work, some things don't, and getting answers involves some detective
work. That said, I don't really have frustration or criticism to aim at Nektos.
Honestly it's just nice that Nektos Act exists and works at all. The root of the
problem appears to lie with GitHub/Microsoft, who have designed and deployed
their infrastructure in a way that does not facilitate this kind of thing.

A very large part of this project, in terms of time and complexity, was
dedicated to ironing out the various kinks that arose when trying to run
cryptography's GHA yaml locally.

I won't describe the workarounds in detail because: the script is still
evolving; I don't quite fully understand some of the workarounds even now; and
finally, those workarounds will not necessarily be relevant for this project in
the long term -- if logic is moved out of GHA yaml and into general purpose
tools, obviating the need for a GHA local runner.

But if interested, you may find some info on the workarounds in the script
itself.

## Running the build and diffing the output

Once I got a basic version of the GHA yaml build running (albeit with some very
kludgy workarounds), the next step was to do a build twice in a row and see how
the output differs. As a first step, this experiment is varying nothing but the
fact that it is two subsequent runs -- everything is identical: the host OS, all
config, etc.

With reproducible builds, a build is reproducible until it isn't. That is, it
may be resilient to certain variables changing, but change some other variables,
and it fails to build reproducibly ("FTBR"). So my first step was to change as
little variables as possible and see if it passed the simple test.

To iterate faster, I also pared down the build matrix to build just one of the
`manylinux` wheels, rather than a whole array. (Actually, at first I didn't -- I
probably should have done this a lot sooner, but I was still interested in the
exploration of "how to execute the yaml logic and what are the limits of local
execution vs cloud".) On my setup, for my script to build a single wheel takes a
couple minutes, vs maybe 20 minutes for an array of them (incomplete array, I
never did get ARM builds working yet). That's assuming you have already
downloaded all relevant OCI layers; it takes several extra minutes in a fresh VM
without the images cached.

The build did not pass the simple test. Hashes were different every time. (Of
course, this was not unexpected.) A look at the actual output (using tools such
as `diffoscope`) showed that there were several factors.

One of them was wheel ZIP metadata, especially timestamps. This was unsurprising
-- I had already encountered it when building other, simpler projects. While it
poses a big problem for reproducibility in the Python ecosystem *as a whole*,
for a single project it is actually quite straightforward to deal with; you can
just run a tool to normalize the timestamps. (One good way is to just set
`SOURCE_DATE_EPOCH` and auditwheel will do it.)

But there was another factor which was more complicated both to diagnose, and to
resolve.

## Rust binary reproducibility issue stemming from `uv build`

I noticed that in subsequent diffs, the rust `.so` file contained in the wheel
was always different, and one main reason was that it contained filesytem paths
in the ELF debug info. Those filesystem paths contained a random temp dir
component, for example `/.tmpmbdRiZ/`.

It was not immediately obvious which tool was responsible for these temp
paths: maturin, cargo, uv, Act, a github action...? Eventually I tracked it down
to `uv`, which uses temp dirs for most of its operations.

As a result of this finding, I filed an issue with `astral-sh/uv`: "Use of
random temp paths by uv build adds nondeterminism into build environments". I
won't describe it in detail here because that would just duplicate what is
already available in the issue tracker:
https://github.com/astral-sh/uv/issues/13096

As regards `cryptography`, as of 2025-04, I have identified several workarounds
for this problem, although none of them are an ideal fix.

As an aside, `cryptography` recently uses `uv` for quite a lot of operations in
their CI and build logic. In fact, not only do they use it, but the cryptography
project has been involved in driving certain feature requests in uv and `uv
build`: https://github.com/pyca/cryptography/issues/11548

## Future

Having made significant progress on this project, and identified some of the
blockers to reproducibility, I filed an issue with `pyca/cryptography`: "Provide
verifiably reproducible wheels on PyPI",
https://github.com/pyca/cryptography/issues/12811

That issue synthesized my findings so far and outlined a potential immediate
path to reproducibility (which would involve several non-ideal workarounds).

I am also taking the results of this experiment and trying to apply them to
create more ideal, scalable/lasting solutions, for `cryptography` and any other
Python project. I have begun filing issues with various projects in the Python
tooling ecosystem, for example about normalizing wheel ZIP metadata. I am also
working on some notes about deterministic wheels, which I hope will help move
forward the conversation about it for the Python ecosystem as a whole.

As for the scripts from this project, if you try them now, they should probably
run. But they are not finished (and may never be -- since their purpose is to
uncover issues to be fixed elsewhere). Be aware that the script is not cleaned
up at all, it includes unused codepaths and some comments may be misleading.

