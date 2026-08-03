#!/usr/bin/env bash
set -o errexit

# Install jemalloc for reduced memory usage and fragmentation
apt-get update -qq && apt-get install --no-install-recommends -y libjemalloc2

# ci (not install) so the build resolves exactly what package-lock.json pins —
# daisyui is consumed by the Tailwind build during assets:precompile.
npm ci
bundle install

# app/assets/svg/icons is gitignored (see docs/ASSETS.md): the Phosphor set is
# synced per checkout rather than committed, so it has to be fetched here too or
# every icon(...) call raises Icons::IconNotFound at request time. CI does the
# same, keyed on a cache. Redirecting stdin keeps the gem's interactive
# "remove the temp files?" prompt from stalling a non-interactive build if the
# upstream clone fails.
bundle exec rails generate rails_icons:sync --library=phosphor --force --quiet </dev/null

bundle exec rails assets:precompile
bundle exec rails assets:clean

# db:migrate deliberately does NOT run here — it is the service's
# preDeployCommand (see render.yaml). Render runs that after the build and
# before traffic switches, so a failed migration halts the deploy with the
# previous version still serving.
