# Contributing

## How to contribute

- **Found a bug or have an idea?** Open an
  [issue](https://github.com/capivaraos/capivaraos-herd/issues) using the
  templates.
- **Security vulnerability?** Do **not** open a public issue — follow
  [SECURITY.md](SECURITY.md).
- **Want to send code?** Fork, branch from `main`, make focused changes (see the
  [README](README.md) to build images/RPMs), and open a pull request saying
  what changes, the effect for users and how it was tested. A maintainer will
  review.

## Writing commits, comments and pull requests

**Commit messages** say what changed, in the imperative, in a subject line of at most 72 characters. An optional short body describes the effect for users and how the change was tested.

```
Fix invisible passphrase field on the disk unlock screen

The field is now drawn above the theme background. Tested in a VM
with an encrypted install, UEFI and legacy BIOS.
```

**Code comments** explain what the code cannot show by itself: a non-obvious technical constraint. Do not use comments for change history, dates, or who asked for what. Version control already records that.

**Branch names** follow `type/short-description`, where type is one of `feat`, `fix`, `docs`, `chore`, `build`, `test`, `release`.

**Pull requests** do one thing. Fill in the three fields of the template and keep each to a few lines.

**Security issues** are reported privately, as described in [SECURITY.md](SECURITY.md), never in a public issue or pull request.

**Never commit** secrets, personal data, e-mail addresses, or paths and user names from your own machine. Use placeholders such as `/home/USER` in examples.

A `Guards` check runs on every pull request. If it reports that a file, message or name does not follow these guidelines, rewrite it and push again.

## License

By contributing, you agree to license your code under **GPLv3** (see
[LICENSE](LICENSE)); the "CapivaraOS" name and logo are the project's trademark
(see [TRADEMARK.md](TRADEMARK.md)). Please follow our
[Code of Conduct](CODE_OF_CONDUCT.md).
