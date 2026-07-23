#!/usr/bin/env bash
set -o errexit

# Install jemalloc for reduced memory usage and fragmentation
apt-get update -qq && apt-get install --no-install-recommends -y libjemalloc2

npm install
bundle install
bundle exec rails assets:precompile
bundle exec rails db:migrate
