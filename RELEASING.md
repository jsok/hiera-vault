# Release Process

## Git commit and tag

Create a new commit which updates the `gem.version` field in `hiera-vault.gemspec`.

Then:

    git commit -m "vx.y.z release"
    git push
    git tag vx.y.z
    git push --tags

## Rubygems.org

### TravisCI

The new tagged version should be released automatically.

### Manual

Now build the gem:

    gem build hiera-vault.gemspec

And push it to rubygems.org, it will prompt for credentials if necessary:

    gem push hiera-vault-x.y.z.gem
