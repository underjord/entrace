# Changelog

## v0.2.0

You never have this library installed when you need it. So let's fix that.

- Add experimental install support. For installing as pre-built BEAM files into a running system with a one-liner.
- Add Entrace.Mini, installable convenience version of the library that is one pasteable module.

This will also spread into your cluster

Obviously use at your own risk as your are installing a random chunk of code across your cluster.

## v0.1.1

Expand compatibility back to at least OTP 24, probably further. This was achieved by making calls skip the `:call_memory` option if less than OTP-26.

## v0.1.0

Initial release.
