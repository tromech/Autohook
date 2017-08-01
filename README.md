# Autohook

**Autohook** is a very, _very_ small Git hook "framework".

It consists of one Bash script which acts as the entry point for all the hooks, and which runs scripts based on file names.

[![Say Thanks!](https://img.shields.io/badge/Say%20Thanks-!-1EAEDB.svg)](https://saythanks.io/to/nkantar)

## Example

Let's say you have a cleanup script you want run before commits, aka as a `pre-commit` hook. Here's what you could do:

1. In your repo, put `autohook.sh` inside `hooks/`.
2. Name the script you actually want to run something like `pre-commit-cleanup.sh` and put it inside `hooks/` as well.
3. Symlink `.git/hooks/pre-commit` to `hooks/autohook.sh`.
4. You're done.
5. _Rejoice!_ :tada:

For **multiple scripts** to be run by the same hook, add them with the hook name at the beginning. You can enforce order with numbers (e.g., `pre-commit-1-cleanup.sh`, `pre-commit-2-other-stuff.sh`).

For **multiple hooks**, symlink them to `autohook.sh` and name your scripts accordingly.

## Contributing

Contributions of all sorts are welcome, be they bug reports, patches, or even just feedback. Creating a [new issue](https://github.com/nkantar/Autohook/issues/new 'New Issue') or [pull request](https://github.com/nkantar/Autohook/compare 'New Pull Request') is probably the best way to get started.

Please note that this project is released with a [Contributor Code of Conduct](https://github.com/nkantar/Autohook/blob/master/CODE_OF_CONDUCT.md 'Autohook Code of Conduct'). By participating in this project you agree to abide by its terms.

## License

This software is licensed under the _MIT License_. Please see the included `LICENSE.txt` for details.

